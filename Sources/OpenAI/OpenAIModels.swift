import Foundation

struct DetectedLanguage: Decodable, Sendable, Equatable {
    let language: String
    let probability: Double?
}

extension DetectedLanguage {
    private enum CodingKeys: String, CodingKey {
        case language
        case code
        case probability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let language = try container.decodeIfPresent(String.self, forKey: .language) {
            self.language = language
        } else {
            language = try container.decode(String.self, forKey: .code)
        }
        probability = try container.decodeIfPresent(Double.self, forKey: .probability)
    }
}

struct TranscriptionResponse: Decodable, Sendable, Equatable {
    let text: String
    let languages: [DetectedLanguage]?
}

struct DiarizedTranscriptionResponse: Codable, Sendable, Equatable {
    let text: String?
    let segments: [DiarizedSegment]
}

struct DiarizedSegment: Codable, Sendable, Equatable {
    let speaker: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

enum OpenAIClientError: Error, Sendable, Equatable {
    case api
    case transientAPI
    case uploadTooLarge(maximumBytes: Int)
    case unreadableAudioFile
    case invalidResponse
}

extension OpenAIClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .api:
            "OpenAI rejected the request."
        case .transientAPI:
            "OpenAI is temporarily unavailable."
        case let .uploadTooLarge(maximumBytes):
            "The audio file exceeds the \(maximumBytes)-byte upload limit."
        case .unreadableAudioFile:
            "The audio file could not be read."
        case .invalidResponse:
            "OpenAI returned an invalid response."
        }
    }
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
