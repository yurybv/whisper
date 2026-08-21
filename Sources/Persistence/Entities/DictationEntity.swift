import Foundation
import SwiftData

enum DictationStatus: String, Sendable, Codable, Equatable {
    case processing
    case ready
    case failed
    case cancelled
}

struct DictationDraft: Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let modeID: UUID?
    let modeNameSnapshot: String
    let modeInstructionsSnapshot: String
    let detectedLanguages: [String]
    let originalText: String
    let outputText: String
    let targetApplicationBundleID: String?
    let status: DictationStatus
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        modeID: UUID? = nil,
        modeNameSnapshot: String,
        modeInstructionsSnapshot: String,
        detectedLanguages: [String] = [],
        originalText: String = "",
        outputText: String = "",
        targetApplicationBundleID: String? = nil,
        status: DictationStatus = .processing,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.modeID = modeID
        self.modeNameSnapshot = modeNameSnapshot
        self.modeInstructionsSnapshot = modeInstructionsSnapshot
        self.detectedLanguages = detectedLanguages
        self.originalText = originalText
        self.outputText = outputText
        self.targetApplicationBundleID = targetApplicationBundleID
        self.status = status
        self.errorMessage = errorMessage
    }
}

struct DictationSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let modeID: UUID?
    let modeNameSnapshot: String
    let modeInstructionsSnapshot: String
    let detectedLanguages: [String]
    let originalText: String
    let outputText: String
    let targetApplicationBundleID: String?
    let status: DictationStatus
    let errorMessage: String?
}

enum DictationMutation: Sendable, Equatable {
    case status(DictationStatus, errorMessage: String?)
    case result(
        originalText: String,
        outputText: String,
        detectedLanguages: [String],
        duration: TimeInterval
    )
}

@Model
final class DictationEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var modeID: UUID?
    var modeNameSnapshot: String
    var modeInstructionsSnapshot: String
    var detectedLanguages: [String]
    var originalText: String
    var outputText: String
    var targetApplicationBundleID: String?
    var statusRaw: String
    var errorMessage: String?

    init(_ draft: DictationDraft) {
        id = draft.id
        createdAt = draft.createdAt
        duration = draft.duration
        modeID = draft.modeID
        modeNameSnapshot = draft.modeNameSnapshot
        modeInstructionsSnapshot = draft.modeInstructionsSnapshot
        detectedLanguages = draft.detectedLanguages
        originalText = draft.originalText
        outputText = draft.outputText
        targetApplicationBundleID = draft.targetApplicationBundleID
        statusRaw = draft.status.rawValue
        errorMessage = draft.errorMessage
    }

    var snapshot: DictationSnapshot? {
        guard let status = DictationStatus(rawValue: statusRaw) else {
            return nil
        }
        return DictationSnapshot(
            id: id,
            createdAt: createdAt,
            duration: duration,
            modeID: modeID,
            modeNameSnapshot: modeNameSnapshot,
            modeInstructionsSnapshot: modeInstructionsSnapshot,
            detectedLanguages: detectedLanguages,
            originalText: originalText,
            outputText: outputText,
            targetApplicationBundleID: targetApplicationBundleID,
            status: status,
            errorMessage: errorMessage
        )
    }

    func apply(_ mutation: DictationMutation) {
        switch mutation {
        case let .status(status, errorMessage):
            statusRaw = status.rawValue
            self.errorMessage = errorMessage
        case let .result(originalText, outputText, detectedLanguages, duration):
            self.originalText = originalText
            self.outputText = outputText
            self.detectedLanguages = detectedLanguages
            self.duration = duration
        }
    }
}
