import Foundation

enum DictationState: Equatable, Sendable {
    case idle
    case recording(modeName: String)
    case transcribing
    case transforming
    case inserting
    case completed
    case failed(message: String, textOnClipboard: Bool)
}
