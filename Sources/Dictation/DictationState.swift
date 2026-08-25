import Foundation

enum DictationRecovery: Equatable, Sendable {
    case none
    case retryOrDiscard
    case discardOnly

    var canRetry: Bool { self == .retryOrDiscard }
    var canDiscard: Bool { self != .none }
}

enum DictationState: Equatable, Sendable {
    case idle
    case recording(modeName: String)
    case transcribing
    case transforming
    case inserting
    case completed(InsertionResult)
    case failed(message: String, textOnClipboard: Bool, recovery: DictationRecovery)
}
