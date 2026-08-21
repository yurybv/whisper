import Foundation

enum FeatureError: Error, Sendable, Equatable {
    case keychain
    case invalidAPIKey
    case microphoneDisconnected
}
