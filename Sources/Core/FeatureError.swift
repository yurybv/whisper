import Foundation

enum FeatureError: Error, Sendable, Equatable {
    case keychain
    case invalidAPIKey
    case microphoneDisconnected
}

extension FeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .keychain:
            "Whisper could not access the API key in Keychain."
        case .invalidAPIKey:
            "Open Whisper Settings to add or replace your OpenAI API key."
        case .microphoneDisconnected:
            "The microphone disconnected. Reconnect it and start a new dictation."
        }
    }
}

enum DictationErrorPresentation {
    static func message(for error: Error, recovery: DictationRecovery) -> String {
        let baseMessage: String

        switch error {
        case FeatureError.invalidAPIKey:
            baseMessage = "Open Whisper Settings to add or replace your OpenAI API key."
        case FeatureError.keychain:
            baseMessage = "Whisper could not read the API key from Keychain. Open Settings and try again."
        case FeatureError.microphoneDisconnected:
            baseMessage = "The microphone disconnected. Reconnect it and start a new dictation."
        case is MicrophoneCaptureFailure:
            baseMessage = "The microphone disconnected. The available audio was finalized."
        case is URLError:
            baseMessage = "Check your network connection."
        case let error as TextInsertionError:
            baseMessage = error.localizedDescription
        case let error as OpenAIClientError:
            baseMessage = openAIMessage(for: error)
        default:
            baseMessage = "Whisper could not finish this dictation."
        }

        switch recovery {
        case .none:
            return baseMessage
        case .retryOrDiscard:
            return "\(baseMessage) Audio is saved. Choose Retry or Discard."
        case .discardOnly:
            return "\(baseMessage) Audio is saved. Choose Discard."
        }
    }

    private static func openAIMessage(for error: OpenAIClientError) -> String {
        switch error {
        case .uploadTooLarge:
            "The recording is too long to upload. Discard it and record a shorter dictation."
        case .unreadableAudioFile:
            "Whisper could not read the captured audio."
        case .invalidResponse, .api:
            "OpenAI could not process this dictation."
        }
    }
}
