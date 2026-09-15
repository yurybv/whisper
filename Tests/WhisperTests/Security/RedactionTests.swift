import Foundation
import XCTest
@testable import Whisper

final class RedactionTests: XCTestCase {
    func testProviderFailuresNeverExposePrivateResponseTextInDescriptions() async throws {
        let privateValues = [
            "sk-test-private-fixture",
            "Authorization: Bearer fixture",
            "dictated private fixture",
            "instruction private fixture",
        ]
        let providerPayload = privateValues.joined(separator: " | ")
        let store: any SecureStore = InMemorySecureStore()
        try store.saveOpenAIKey(privateValues[0])
        let session = PrivatePayloadSession(payload: providerPayload)
        let client = OpenAIClient(
            secureStore: store,
            session: session,
            retryPolicy: RetryPolicy(delays: [])
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperRedaction-\(UUID().uuidString).m4a")
        try Data([0, 1, 2]).write(to: audioURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let error: Error
        do {
            _ = try await client.transcribe(fileURL: audioURL, languageHint: nil, prompt: nil)
            return XCTFail("Expected the private provider response to fail")
        } catch let caught {
            error = caught
        }

        let formattedValues = [
            error.localizedDescription,
            String(describing: error),
            String(reflecting: error),
            DictationErrorPresentation.message(for: error, recovery: .retryOrDiscard),
        ]
        for formatted in formattedValues {
            for privateValue in privateValues {
                XCTAssertFalse(formatted.contains(privateValue))
            }
        }
    }
}

private actor PrivatePayloadSession: URLSessionProtocol {
    let payload: String

    init(payload: String) {
        self.payload = payload
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data(#"{"error":{"message":"\#(payload)"}}"#.utf8)
        return (body, response)
    }
}
