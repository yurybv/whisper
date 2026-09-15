import Foundation
import SwiftData

enum RecentHistoryKind: Equatable, Sendable {
    case dictation
    case recording
}

struct RecentHistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: RecentHistoryKind
    let date: Date
    let title: String
    let preview: String
    let status: String
}

struct HistorySnapshot: Equatable, Sendable {
    let dictations: [DictationSnapshot]
    let meetings: [MeetingSnapshot]
    let segmentsByMeetingID: [UUID: [TranscriptSegment]]
}

@MainActor
protocol HistoryReading {
    func historySnapshot() throws -> HistorySnapshot
}

@MainActor
protocol HistoryRepositoryProtocol {
    func createDictation(_ draft: DictationDraft) throws -> UUID
    func updateDictation(id: UUID, mutation: DictationMutation) throws
    func createMeeting(_ draft: MeetingDraft) throws -> UUID
    func updateMeeting(id: UUID, mutation: MeetingMutation) throws
    func replaceSegments(meetingID: UUID, segments: [TranscriptSegment]) throws
    func incompleteMeetings() throws -> [MeetingSnapshot]
    func deleteDictation(id: UUID) throws
    func deleteMeeting(id: UUID) throws
    func historySnapshot() throws -> HistorySnapshot
}

@MainActor
final class HistoryRepository: HistoryRepositoryProtocol, HistoryReading {
    private let context: ModelContext
    private let recordingDirectoryCleaner: (any RecordingDirectoryCleaning)?

    init(context: ModelContext, appPaths: AppPaths? = nil) {
        self.context = context
        recordingDirectoryCleaner = appPaths.map(AppPathsRecordingDirectoryCleaner.init(paths:))
    }

    init(context: ModelContext, recordingDirectoryCleaner: any RecordingDirectoryCleaning) {
        self.context = context
        self.recordingDirectoryCleaner = recordingDirectoryCleaner
    }

    func createDictation(_ draft: DictationDraft) throws -> UUID {
        context.insert(DictationEntity(draft))
        try context.save()
        return draft.id
    }

    func updateDictation(id: UUID, mutation: DictationMutation) throws {
        guard let entity = try dictationEntity(id: id) else {
            throw PersistenceError.dictationNotFound
        }
        entity.apply(mutation)
        try context.save()
    }

    func dictation(id: UUID) throws -> DictationSnapshot? {
        try dictationEntity(id: id)?.snapshot
    }

    func createMeeting(_ draft: MeetingDraft) throws -> UUID {
        context.insert(MeetingEntity(draft))
        try context.save()
        return draft.id
    }

    func updateMeeting(id: UUID, mutation: MeetingMutation) throws {
        guard let entity = try meetingEntity(id: id) else {
            throw PersistenceError.meetingNotFound
        }
        entity.apply(mutation)
        try context.save()
    }

    func replaceSegments(meetingID: UUID, segments: [TranscriptSegment]) throws {
        guard let meeting = try meetingEntity(id: meetingID) else {
            throw PersistenceError.meetingNotFound
        }
        guard segments.allSatisfy({ $0.meetingID == meetingID }) else {
            throw PersistenceError.segmentMeetingMismatch
        }

        for segment in meeting.segments {
            context.delete(segment)
        }
        try context.save()
        for segment in segments {
            let entity = TranscriptSegmentEntity(segment, meeting: meeting)
            context.insert(entity)
        }
        try context.save()
    }

    func incompleteMeetings() throws -> [MeetingSnapshot] {
        let descriptor = FetchDescriptor<MeetingEntity>(
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
            .compactMap(\.snapshot)
            .filter { $0.status.isIncomplete }
    }

    func meeting(id: UUID) throws -> MeetingSnapshot? {
        try meetingEntity(id: id)?.snapshot
    }

    func transcriptSegments(meetingID: UUID) throws -> [TranscriptSegment] {
        guard let meeting = try meetingEntity(id: meetingID) else {
            throw PersistenceError.meetingNotFound
        }
        return meeting.segments.map(\.segment).sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.endTime < $1.endTime
        }
    }

    func recentHistory(limit: Int) throws -> [RecentHistoryItem] {
        guard limit > 0 else { return [] }
        var dictationDescriptor = FetchDescriptor<DictationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        dictationDescriptor.fetchLimit = limit
        var meetingDescriptor = FetchDescriptor<MeetingEntity>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        meetingDescriptor.fetchLimit = limit

        let dictations = try context.fetch(dictationDescriptor)
            .compactMap(\.snapshot)
            .map {
                RecentHistoryItem(
                    id: $0.id,
                    kind: .dictation,
                    date: $0.createdAt,
                    title: $0.modeNameSnapshot,
                    preview: $0.outputText.isEmpty ? $0.originalText : $0.outputText,
                    status: $0.status.rawValue.capitalized
                )
            }
        let meetings = try context.fetch(meetingDescriptor)
            .compactMap(\.snapshot)
            .map {
                RecentHistoryItem(
                    id: $0.id,
                    kind: .recording,
                    date: $0.startedAt,
                    title: $0.title,
                    preview: $0.processedText,
                    status: $0.status.rawValue.capitalized
                )
            }
        return Array(
            (dictations + meetings)
                .sorted { $0.date > $1.date }
                .prefix(max(0, limit))
        )
    }

    func historySnapshot() throws -> HistorySnapshot {
        let dictations = try context.fetch(
            FetchDescriptor<DictationEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        ).compactMap(\.snapshot)
        let meetings = try context.fetch(
            FetchDescriptor<MeetingEntity>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        ).compactMap(\.snapshot)
        let segments = try context.fetch(
            FetchDescriptor<TranscriptSegmentEntity>(
                sortBy: [
                    SortDescriptor(\.startTime),
                    SortDescriptor(\.endTime),
                ]
            )
        ).map(\.segment)
        return HistorySnapshot(
            dictations: dictations,
            meetings: meetings,
            segmentsByMeetingID: Dictionary(grouping: segments, by: \.meetingID)
        )
    }

    func deleteDictation(id: UUID) throws {
        guard let entity = try dictationEntity(id: id) else {
            throw PersistenceError.dictationNotFound
        }
        context.delete(entity)
        try context.save()
    }

    func deleteMeeting(id: UUID) throws {
        guard let entity = try meetingEntity(id: id) else {
            throw PersistenceError.meetingNotFound
        }
        if recordingDirectoryCleaner != nil {
            context.insert(RecordingCleanupEntity(meetingID: id))
        }
        for segment in entity.segments {
            context.delete(segment)
        }
        context.delete(entity)
        try context.save()
        try? retryPendingFileCleanup()
    }

    @discardableResult
    func retryPendingFileCleanup() throws -> [UUID] {
        guard let recordingDirectoryCleaner else { return [] }
        let cleanups = try context.fetch(
            FetchDescriptor<RecordingCleanupEntity>(sortBy: [SortDescriptor(\.createdAt)])
        )
        var pending: [UUID] = []
        for cleanup in cleanups {
            guard cleanup.relativeDirectoryPath == "meeting-\(cleanup.meetingID.uuidString)" else {
                pending.append(cleanup.meetingID)
                continue
            }
            do {
                try recordingDirectoryCleaner.deleteRecordingDirectory(for: cleanup.meetingID)
                context.delete(cleanup)
                try context.save()
            } catch {
                pending.append(cleanup.meetingID)
            }
        }
        return pending
    }

    private func dictationEntity(id: UUID) throws -> DictationEntity? {
        try context.fetch(FetchDescriptor<DictationEntity>())
            .first { $0.id == id }
    }

    private func meetingEntity(id: UUID) throws -> MeetingEntity? {
        try context.fetch(FetchDescriptor<MeetingEntity>())
            .first { $0.id == id }
    }
}
