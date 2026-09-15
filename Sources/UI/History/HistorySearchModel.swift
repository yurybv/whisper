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
@Observable
final class HistorySearchModel {
    private let repository: any HistoryReading
    private let calendar: Calendar
    private let now: () -> Date

    var query = "" {
        didSet { reconcileSelection() }
    }
    var filter: HistoryFilter = .all {
        didSet { reconcileSelection() }
    }
    private(set) var entries: [HistoryEntry] = []
    private(set) var selectedID: UUID?
    private(set) var errorMessage: String?

    init(
        repository: any HistoryReading,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
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
        selectedID = id
    }

    private func groupTitle(for date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now()) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now()),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func reconcileSelection() {
        let visibleEntries = filteredEntries
        if let selectedID, visibleEntries.contains(where: { $0.id == selectedID }) { return }
        selectedID = visibleEntries.first?.id
    }

    private static func newestFirst(_ lhs: HistoryEntry, _ rhs: HistoryEntry) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
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
