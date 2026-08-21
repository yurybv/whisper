import Foundation
import SwiftData

enum MeetingStatus: String, Sendable, Codable, Equatable {
    case recording
    case finalizing
    case captured
    case transcribing
    case processing
    case ready
    case failed

    var isIncomplete: Bool {
        self != .ready && self != .failed
    }
}

struct MeetingDraft: Sendable, Equatable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let duration: TimeInterval
    let status: MeetingStatus
    let progressCompleted: Int
    let progressTotal: Int
    let instructionsSnapshot: String
    let resultLanguage: String?
    let microphoneRelativePath: String
    let systemAudioRelativePath: String
    let processedText: String
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        status: MeetingStatus = .recording,
        progressCompleted: Int = 0,
        progressTotal: Int = 0,
        instructionsSnapshot: String,
        resultLanguage: String? = nil,
        microphoneRelativePath: String = "",
        systemAudioRelativePath: String = "",
        processedText: String = "",
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.status = status
        self.progressCompleted = progressCompleted
        self.progressTotal = progressTotal
        self.instructionsSnapshot = instructionsSnapshot
        self.resultLanguage = resultLanguage
        self.microphoneRelativePath = microphoneRelativePath
        self.systemAudioRelativePath = systemAudioRelativePath
        self.processedText = processedText
        self.errorMessage = errorMessage
    }
}

struct MeetingSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let duration: TimeInterval
    let status: MeetingStatus
    let progressCompleted: Int
    let progressTotal: Int
    let instructionsSnapshot: String
    let resultLanguage: String?
    let microphoneRelativePath: String
    let systemAudioRelativePath: String
    let processedText: String
    let errorMessage: String?
}

enum MeetingMutation: Sendable, Equatable {
    case title(String)
    case status(MeetingStatus, errorMessage: String?)
    case progress(completed: Int, total: Int)
    case capture(
        endedAt: Date,
        duration: TimeInterval,
        microphoneRelativePath: String,
        systemAudioRelativePath: String
    )
    case result(processedText: String, resultLanguage: String?)
}

@Model
final class MeetingEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval
    var statusRaw: String
    var progressCompleted: Int
    var progressTotal: Int
    var instructionsSnapshot: String
    var resultLanguage: String?
    var microphoneRelativePath: String
    var systemAudioRelativePath: String
    var processedText: String
    var errorMessage: String?
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegmentEntity.meeting)
    var segments: [TranscriptSegmentEntity] = []

    init(_ draft: MeetingDraft) {
        id = draft.id
        title = draft.title
        startedAt = draft.startedAt
        endedAt = draft.endedAt
        duration = draft.duration
        statusRaw = draft.status.rawValue
        progressCompleted = draft.progressCompleted
        progressTotal = draft.progressTotal
        instructionsSnapshot = draft.instructionsSnapshot
        resultLanguage = draft.resultLanguage
        microphoneRelativePath = draft.microphoneRelativePath
        systemAudioRelativePath = draft.systemAudioRelativePath
        processedText = draft.processedText
        errorMessage = draft.errorMessage
    }

    var snapshot: MeetingSnapshot? {
        guard let status = MeetingStatus(rawValue: statusRaw) else {
            return nil
        }
        return MeetingSnapshot(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: duration,
            status: status,
            progressCompleted: progressCompleted,
            progressTotal: progressTotal,
            instructionsSnapshot: instructionsSnapshot,
            resultLanguage: resultLanguage,
            microphoneRelativePath: microphoneRelativePath,
            systemAudioRelativePath: systemAudioRelativePath,
            processedText: processedText,
            errorMessage: errorMessage
        )
    }

    func apply(_ mutation: MeetingMutation) {
        switch mutation {
        case let .title(title):
            self.title = title
        case let .status(status, errorMessage):
            statusRaw = status.rawValue
            self.errorMessage = errorMessage
        case let .progress(completed, total):
            progressCompleted = completed
            progressTotal = total
        case let .capture(endedAt, duration, microphoneRelativePath, systemAudioRelativePath):
            self.endedAt = endedAt
            self.duration = duration
            self.microphoneRelativePath = microphoneRelativePath
            self.systemAudioRelativePath = systemAudioRelativePath
        case let .result(processedText, resultLanguage):
            self.processedText = processedText
            self.resultLanguage = resultLanguage
        }
    }
}
