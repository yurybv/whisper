import Foundation

struct DetectedLanguage: Decodable, Sendable, Equatable {
    let language: String
    let probability: Double?
}

struct TranscriptionResponse: Decodable, Sendable, Equatable {
    let text: String
    let languages: [DetectedLanguage]?
}

struct DiarizedTranscriptionResponse: Decodable, Sendable, Equatable {
    let text: String?
    let segments: [DiarizedSegment]
}

struct DiarizedSegment: Decodable, Sendable, Equatable {
    let speaker: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

enum OpenAIClientError: Error, Sendable, Equatable {
    case api(message: String)
    case uploadTooLarge(maximumBytes: Int)
    case unreadableAudioFile
    case invalidResponse
}

extension OpenAIClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .api(message):
            message
        case let .uploadTooLarge(maximumBytes):
            "The audio file exceeds the \(maximumBytes)-byte upload limit."
        case .unreadableAudioFile:
            "The audio file could not be read."
        case .invalidResponse:
            "OpenAI returned an invalid response."
        }
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

struct ResponsesAPIResponse: Decodable, Sendable {
    struct Output: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            let type: String
            let text: String?
        }

        let type: String
        let content: [Content]?
    }

    let output: [Output]

    var outputText: String? {
        output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .first { $0.type == "output_text" }?
            .text
    }
}

extension JSONDecoder {
    func decodeOpenAIError(from data: Data) -> String? {
        try? decode(OpenAIErrorEnvelope.self, from: data).error.message
    }
}
