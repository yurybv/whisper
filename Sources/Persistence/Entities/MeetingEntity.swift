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

enum MeetingFailureKind: String, Sendable, Codable, Equatable {
    case authentication
    case missingAPIKey
    case network
    case capture
    case processing
    case interruptedCapture

    var isRetryable: Bool { self == .network || self == .missingAPIKey }
}

enum MeetingRetryStage: String, Sendable, Codable, Equatable {
    case transcription
    case processing
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
    let microphoneStartOffset: TimeInterval
    let systemAudioStartOffset: TimeInterval
    let processedText: String
    let errorMessage: String?
    let failureKind: MeetingFailureKind?
    let retryStage: MeetingRetryStage?

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
        microphoneStartOffset: TimeInterval = 0,
        systemAudioStartOffset: TimeInterval = 0,
        processedText: String = "",
        errorMessage: String? = nil,
        failureKind: MeetingFailureKind? = nil,
        retryStage: MeetingRetryStage? = nil
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
        self.microphoneStartOffset = microphoneStartOffset
        self.systemAudioStartOffset = systemAudioStartOffset
        self.processedText = processedText
        self.errorMessage = errorMessage
        self.failureKind = failureKind
        self.retryStage = retryStage
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
    let microphoneStartOffset: TimeInterval
    let systemAudioStartOffset: TimeInterval
    let processedText: String
    let errorMessage: String?
    let failureKind: MeetingFailureKind?
    let retryStage: MeetingRetryStage?
}

enum MeetingMutation: Sendable, Equatable {
    case title(String)
    case status(MeetingStatus, errorMessage: String?)
    case retryable(
        message: String,
        kind: MeetingFailureKind,
        stage: MeetingRetryStage
    )
    case failure(message: String, kind: MeetingFailureKind, stage: MeetingRetryStage?)
    case progress(completed: Int, total: Int)
    case capture(
        endedAt: Date,
        duration: TimeInterval,
        microphoneRelativePath: String,
        systemAudioRelativePath: String,
        microphoneStartOffset: TimeInterval,
        systemAudioStartOffset: TimeInterval
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
    var microphoneStartOffset: TimeInterval = 0
    var systemAudioStartOffset: TimeInterval = 0
    var processedText: String
    var errorMessage: String?
    var failureKindRaw: String?
    var retryStageRaw: String?
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
        microphoneStartOffset = draft.microphoneStartOffset
        systemAudioStartOffset = draft.systemAudioStartOffset
        processedText = draft.processedText
        errorMessage = draft.errorMessage
        failureKindRaw = draft.failureKind?.rawValue
        retryStageRaw = draft.retryStage?.rawValue
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
            microphoneStartOffset: microphoneStartOffset,
            systemAudioStartOffset: systemAudioStartOffset,
            processedText: processedText,
            errorMessage: errorMessage,
            failureKind: failureKindRaw.flatMap(MeetingFailureKind.init(rawValue:)),
            retryStage: retryStageRaw.flatMap(MeetingRetryStage.init(rawValue:))
        )
    }

    func apply(_ mutation: MeetingMutation) {
        switch mutation {
        case let .title(title):
            self.title = title
        case let .status(status, errorMessage):
            statusRaw = status.rawValue
            self.errorMessage = errorMessage
            failureKindRaw = nil
            retryStageRaw = nil
        case let .retryable(message, kind, stage):
            statusRaw = MeetingStatus.captured.rawValue
            errorMessage = message
            failureKindRaw = kind.rawValue
            retryStageRaw = stage.rawValue
        case let .failure(message, kind, stage):
            statusRaw = MeetingStatus.failed.rawValue
            errorMessage = message
            failureKindRaw = kind.rawValue
            retryStageRaw = stage?.rawValue
        case let .progress(completed, total):
            progressCompleted = completed
            progressTotal = total
        case let .capture(
            endedAt,
            duration,
            microphoneRelativePath,
            systemAudioRelativePath,
            microphoneStartOffset,
            systemAudioStartOffset
        ):
            self.endedAt = endedAt
            self.duration = duration
            self.microphoneRelativePath = microphoneRelativePath
            self.systemAudioRelativePath = systemAudioRelativePath
            self.microphoneStartOffset = microphoneStartOffset
            self.systemAudioStartOffset = systemAudioStartOffset
        case let .result(processedText, resultLanguage):
            self.processedText = processedText
            self.resultLanguage = resultLanguage
        }
    }
}
