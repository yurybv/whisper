import Foundation
import SwiftData

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
}

@MainActor
final class HistoryRepository: HistoryRepositoryProtocol {
    private let context: ModelContext
    private let appPaths: AppPaths?

    init(context: ModelContext, appPaths: AppPaths? = nil) {
        self.context = context
        self.appPaths = appPaths
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
        try appPaths?.deleteRecordingDirectory(for: id)
        for segment in entity.segments {
            context.delete(segment)
        }
        try context.save()
        context.delete(entity)
        try context.save()
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
