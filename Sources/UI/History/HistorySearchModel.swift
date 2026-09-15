import Foundation
import Observation

enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case dictations = "Dictations"
    case recordings = "Recordings"

    var id: String { rawValue }
}

enum HistoryEntryContent: Equatable, Sendable {
    case dictation(DictationSnapshot)
    case recording(MeetingSnapshot, [TranscriptSegment])
}

struct HistoryEntry: Identifiable, Equatable, Sendable {
    let content: HistoryEntryContent

    var id: UUID {
        switch content {
        case let .dictation(value): value.id
        case let .recording(value, _): value.id
        }
    }

    var date: Date {
        switch content {
        case let .dictation(value): value.createdAt
        case let .recording(value, _): value.startedAt
        }
    }

    var filter: HistoryFilter {
        switch content {
        case .dictation: .dictations
        case .recording: .recordings
        }
    }

    var title: String {
        switch content {
        case let .dictation(value): value.modeNameSnapshot
        case let .recording(value, _): value.title
        }
    }

    var status: String {
        switch content {
        case let .dictation(value): value.status.rawValue.capitalized
        case let .recording(value, _): value.historyStatus
        }
    }

    var accessibilitySummary: String {
        let type = filter == .dictations ? "Dictation" : "Recording"
        let time = date.formatted(date: .omitted, time: .shortened)
        return "\(type), \(title), \(time), \(status), \(preview)"
    }

    var preview: String {
        switch content {
        case let .dictation(value):
            return Self.nonEmpty(value.outputText) ?? Self.nonEmpty(value.originalText) ?? "No text available"
        case let .recording(value, segments):
            return Self.nonEmpty(value.processedText)
                ?? segments.lazy.compactMap { Self.nonEmpty($0.text) }.first
                ?? value.errorMessage
                ?? "No transcript available"
        }
    }

    func matches(_ normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        let values: [String]
        switch content {
        case let .dictation(value):
            values = [
                value.modeNameSnapshot,
                value.modeInstructionsSnapshot,
                value.originalText,
                value.outputText,
                value.targetApplicationBundleID ?? "",
                value.errorMessage ?? "",
            ]
        case let .recording(value, segments):
            values = [
                value.title,
                value.instructionsSnapshot,
                value.resultLanguage ?? "",
                value.processedText,
                value.errorMessage ?? "",
            ] + segments.map(\.text)
        }
        return values.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct HistoryDateGroup: Identifiable, Equatable, Sendable {
    let date: Date
    let title: String
    let entries: [HistoryEntry]
    var id: Date { date }
}

@MainActor
struct HistoryActions {
    let playbackSources: (MeetingSnapshot) -> [MeetingPlaybackSource]
    let play: (MeetingSnapshot, MeetingPlaybackSource) async throws -> Void
    let stopPlayback: () -> Void
    let retry: (UUID) async throws -> Void
    let reprocess: (UUID) async throws -> Void
    let copy: (HistoryEntry) throws -> Void
    let export: (HistoryEntry, URL) throws -> Void
    let delete: (HistoryEntry) throws -> Void

    static let disabled = HistoryActions(
        playbackSources: { _ in [] },
        play: { _, _ in throw AudioPlaybackError.sourceUnavailable },
        stopPlayback: {},
        retry: { _ in throw MeetingProcessingError.notRetryable },
        reprocess: { _ in throw MeetingProcessingError.transcriptUnavailable },
        copy: { _ in },
        export: { entry, url in try HistoryTextExporter.export(entry, to: url) },
        delete: { _ in }
    )
}

@MainActor
@Observable
final class HistorySearchModel {
    private let repository: any HistoryReading
    private let calendar: Calendar
    private let now: () -> Date
    private var actions: HistoryActions

    var query = "" {
        didSet { reconcileSelection() }
    }
    var filter: HistoryFilter = .all {
        didSet { reconcileSelection() }
    }
    private(set) var entries: [HistoryEntry] = []
    private(set) var selectedID: UUID?
    private(set) var errorMessage: String?
    private(set) var actionMessage: String?
    private(set) var actionErrorMessage: String?
    private(set) var playingMeetingID: UUID?
    private(set) var playingSource: MeetingPlaybackSource?
    private(set) var isRecoveryActionRunning = false
    private var pendingPlaybackMeetingID: UUID?
    private var playbackGeneration = 0

    init(
        repository: any HistoryReading,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        actions: HistoryActions = .disabled
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
        self.actions = actions
    }

    var filteredEntries: [HistoryEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            (filter == .all || entry.filter == filter) && entry.matches(normalized)
        }
    }

    var groups: [HistoryDateGroup] {
        let grouped = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { date in
            HistoryDateGroup(
                date: date,
                title: groupTitle(for: date),
                entries: grouped[date, default: []].sorted(by: Self.newestFirst)
            )
        }
    }

    var selectedEntry: HistoryEntry? {
        guard let selectedID else { return nil }
        return filteredEntries.first { $0.id == selectedID }
    }

    var emptyMessage: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No history matches your search."
        }
        if filter != .all { return "No \(filter.rawValue.lowercased()) yet." }
        return "Your dictations and recordings will appear here."
    }

    func reload() {
        do {
            let snapshot = try repository.historySnapshot()
            entries = (
                snapshot.dictations.map { HistoryEntry(content: .dictation($0)) }
                + snapshot.meetings.map {
                    HistoryEntry(
                        content: .recording(
                            $0,
                            snapshot.segmentsByMeetingID[$0.id, default: []]
                        )
                    )
                }
            ).sorted(by: Self.newestFirst)
            reconcileSelection()
            errorMessage = nil
        } catch {
            entries = []
            selectedID = nil
            errorMessage = "History could not be loaded."
        }
    }

    func select(_ id: UUID?) {
        let playbackMeetingID = playingMeetingID ?? pendingPlaybackMeetingID
        if playbackMeetingID != nil, playbackMeetingID != id {
            stopPlayback()
        }
        selectedID = id
    }

    func setActions(_ actions: HistoryActions) {
        stopPlayback()
        self.actions = actions
    }

    func playbackSources(for meeting: MeetingSnapshot) -> [MeetingPlaybackSource] {
        actions.playbackSources(meeting)
    }

    func play(_ meeting: MeetingSnapshot, source: MeetingPlaybackSource) async {
        playbackGeneration += 1
        let generation = playbackGeneration
        pendingPlaybackMeetingID = meeting.id
        do {
            try await actions.play(meeting, source)
            guard generation == playbackGeneration, selectedID == meeting.id else { return }
            pendingPlaybackMeetingID = nil
            playingMeetingID = meeting.id
            playingSource = source
            actionErrorMessage = nil
        } catch {
            guard generation == playbackGeneration else { return }
            pendingPlaybackMeetingID = nil
            playingMeetingID = nil
            playingSource = nil
            actionErrorMessage = error.localizedDescription
        }
    }

    func stopPlayback() {
        guard playingMeetingID != nil || pendingPlaybackMeetingID != nil else { return }
        playbackGeneration += 1
        actions.stopPlayback()
        pendingPlaybackMeetingID = nil
        playingMeetingID = nil
        playingSource = nil
    }

    func retrySelected() async {
        guard !isRecoveryActionRunning,
              let entry = selectedEntry,
              entry.canRetry else { return }
        await performRecoveryAction(
            meetingID: entry.id,
            successMessage: "Recording retry completed.",
            failureMessage: "The recording could not be retried.",
            action: actions.retry
        )
    }

    func reprocessSelected() async {
        guard !isRecoveryActionRunning,
              let entry = selectedEntry,
              entry.canReprocess else { return }
        await performRecoveryAction(
            meetingID: entry.id,
            successMessage: "Recording reprocessed.",
            failureMessage: "The recording could not be reprocessed.",
            action: actions.reprocess
        )
    }

    func copySelected() {
        guard let entry = selectedEntry else { return }
        guard entry.hasCopyableResult else {
            actionErrorMessage = HistoryActionError.resultUnavailable.localizedDescription
            return
        }
        do {
            try actions.copy(entry)
            actionMessage = "Copied to the clipboard."
            actionErrorMessage = nil
        } catch {
            actionErrorMessage = "The selected text could not be copied."
        }
    }

    func exportSelected(to destination: URL) throws {
        guard let entry = selectedEntry else { return }
        try actions.export(entry, destination)
        actionMessage = "Text exported."
        actionErrorMessage = nil
    }

    func exportSelectedForPresentation(to destination: URL) {
        do {
            try exportSelected(to: destination)
        } catch {
            actionErrorMessage = "The selected text could not be exported."
        }
    }

    func deleteSelected() throws {
        guard let entry = selectedEntry else { return }
        guard entry.canDelete else { throw HistoryActionError.activeItem }
        stopPlayback()
        try actions.delete(entry)
        actionMessage = "History item deleted."
        actionErrorMessage = nil
        reload()
    }

    func deleteSelectedForPresentation() {
        do {
            try deleteSelected()
        } catch HistoryActionError.activeItem {
            actionErrorMessage = HistoryActionError.activeItem.localizedDescription
        } catch {
            actionErrorMessage = "The selected history item could not be deleted."
        }
    }

    private func groupTitle(for date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now()) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now()),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func performRecoveryAction(
        meetingID: UUID,
        successMessage: String,
        failureMessage: String,
        action: (UUID) async throws -> Void
    ) async {
        stopPlayback()
        isRecoveryActionRunning = true
        defer { isRecoveryActionRunning = false }
        do {
            try await action(meetingID)
            reload()
            actionMessage = successMessage
            actionErrorMessage = nil
        } catch {
            reload()
            actionErrorMessage = failureMessage
        }
    }

    private func reconcileSelection() {
        let visibleEntries = filteredEntries
        if let selectedID, visibleEntries.contains(where: { $0.id == selectedID }) { return }
        if playingMeetingID != nil || pendingPlaybackMeetingID != nil { stopPlayback() }
        selectedID = visibleEntries.first?.id
    }

    private static func newestFirst(_ lhs: HistoryEntry, _ rhs: HistoryEntry) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum HistoryActionError: LocalizedError, Equatable {
    case activeItem
    case clipboardUnavailable
    case resultUnavailable

    var errorDescription: String? {
        switch self {
        case .activeItem: "Active or processing items cannot be deleted."
        case .clipboardUnavailable: "The clipboard is unavailable."
        case .resultUnavailable: "No processed result is available to copy."
        }
    }
}

extension HistoryEntry {
    var hasCopyableResult: Bool { HistoryTextExporter.resultText(for: self) != nil }

    var canDelete: Bool {
        switch content {
        case let .dictation(value):
            value.status != .processing
        case let .recording(value, _):
            value.status != .recording
                && value.status != .finalizing
                && value.status != .transcribing
                && value.status != .processing
        }
    }

    var canRetry: Bool {
        guard case let .recording(value, _) = content else { return false }
        return value.failureKind?.isRetryable == true && value.retryStage != nil
    }

    var canReprocess: Bool {
        guard case let .recording(value, segments) = content, !segments.isEmpty else { return false }
        return value.status != .recording
            && value.status != .finalizing
            && value.status != .transcribing
            && value.status != .processing
    }
}

extension MeetingSnapshot {
    var historyStatus: String {
        failureKind?.isRetryable == true ? "Needs Retry" : status.rawValue.capitalized
    }

    var showsActiveProcessingProgress: Bool {
        failureKind == nil
            && progressTotal > 0
            && (status == .transcribing || status == .processing)
    }
}
