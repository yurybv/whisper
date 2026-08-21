import XCTest
@testable import Whisper

@MainActor
final class OpenAIClientTests: XCTestCase {
    func testDictationTranscriptionBuildsMultipartRequestAndDecodesResponse() async throws {
        let session = RecordingURLSession([
            .http(
                statusCode: 200,
                body: Data(#"{"text":"Hello","languages":[{"language":"en","probability":0.99}]}"#.utf8)
            )
        ])
        let client = try makeClient(session: session)
        let fixtureURL = try makeAudioFixture(data: Data("audio-bytes".utf8), extension: "wav")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let response = try await client.transcribe(
            fileURL: fixtureURL,
            languageHint: nil,
            prompt: nil
        )
        let requests = await session.requests()
        let request = try XCTUnwrap(requests.first)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.languages, [DetectedLanguage(language: "en", probability: 0.99)])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(body.contains("gpt-transcribe"))
        XCTAssertTrue(body.contains("audio-bytes"))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("name=\"prompt\""))
    }

    func testDictationIncludesOptionalLanguageAndPrompt() async throws {
        let session = RecordingURLSession([.http(statusCode: 200, body: Data(#"{"text":"Привет"}"#.utf8))])
        let client = try makeClient(session: session)
        let fixtureURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        _ = try await client.transcribe(
            fileURL: fixtureURL,
            languageHint: "ru",
            prompt: "Payload CMS"
        )
        let requests = await session.requests()
        let request = try XCTUnwrap(requests.first)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nru"))
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nPayload CMS"))
    }

    func testDiarizedTranscriptionUsesMeetingModelAndDecodesSegments() async throws {
        let body = Data(#"{"text":"Hello","segments":[{"speaker":"A","text":"Hello","start":0.0,"end":1.25}]}"#.utf8)
        let session = RecordingURLSession([.http(statusCode: 200, body: body)])
        let client = try makeClient(session: session)
        let fixtureURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let response = try await client.transcribeDiarized(fileURL: fixtureURL)
        let requests = await session.requests()
        let request = try XCTUnwrap(requests.first)
        let requestBody = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertEqual(
            response.segments,
            [DiarizedSegment(speaker: "A", text: "Hello", start: 0, end: 1.25)]
        )
        XCTAssertTrue(requestBody.contains("gpt-4o-transcribe-diarize"))
        XCTAssertTrue(requestBody.contains("diarized_json"))
        XCTAssertTrue(requestBody.contains("name=\"chunking_strategy\"\r\n\r\nauto"))
    }

    func testTransformUsesResponsesAPIWithFixedSafetyInstructions() async throws {
        let responseBody = Data(
            #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Natural English"}]}]}"#.utf8
        )
        let session = RecordingURLSession([.http(statusCode: 200, body: responseBody)])
        let client = try makeClient(session: session)

        let output = try await client.transform(
            text: "Продиктованный текст",
            instructions: "Translate into English."
        )
        let requests = await session.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        let textSettings = try XCTUnwrap(json["text"] as? [String: Any])

        XCTAssertEqual(output, "Natural English")
        XCTAssertEqual(request.url?.path, "/v1/responses")
        XCTAssertEqual(json["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(textSettings["verbosity"] as? String, "low")
        XCTAssertEqual(input.map { $0["role"] as? String }, ["developer", "user"])
        XCTAssertTrue(String(describing: input[0]).contains("Do not answer"))
        XCTAssertTrue(String(describing: input[0]).contains("Translate into English."))
        let userContent = try XCTUnwrap(input[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.first?["text"] as? String, "Продиктованный текст")
    }

    func testConnectionUsesConfiguredModelEndpoint() async throws {
        let session = RecordingURLSession([.http(statusCode: 200, body: Data(#"{"id":"gpt-transcribe"}"#.utf8))])
        let client = try makeClient(session: session)

        try await client.testConnection()
        let requests = await session.requests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/models/gpt-transcribe")
    }

    func testInvalidKeyDoesNotRetry() async throws {
        let session = RecordingURLSession([
            .http(statusCode: 401, body: Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8))
        ])
        let client = try makeClient(session: session)
        let fixtureURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        do {
            _ = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)
            XCTFail("Expected invalid API key")
        } catch {
            XCTAssertEqual(error as? FeatureError, .invalidAPIKey)
        }
        let requests = await session.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testRateLimitRetriesThreeTimesWithBoundedBackoff() async throws {
        let session = RecordingURLSession([
            .http(statusCode: 429, body: Data(#"{"error":{"message":"Try later"}}"#.utf8)),
            .http(statusCode: 429, body: Data(#"{"error":{"message":"Try later"}}"#.utf8)),
            .http(statusCode: 429, body: Data(#"{"error":{"message":"Try later"}}"#.utf8)),
            .http(statusCode: 200, body: Data(#"{"text":"Recovered"}"#.utf8))
        ])
        let delays = DelayRecorder()
        let client = try makeClient(
            session: session,
            sleep: { delay in await delays.record(delay) }
        )
        let fixtureURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let response = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)

        XCTAssertEqual(response.text, "Recovered")
        let requests = await session.requests()
        let recordedDelays = await delays.values()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(recordedDelays, [1, 2, 4])
    }

    func testBadRequestExposesOnlyServerMessage() async throws {
        let session = RecordingURLSession([
            .http(statusCode: 400, body: Data(#"{"error":{"message":"Unsupported audio format"}}"#.utf8))
        ])
        let client = try makeClient(session: session)
        let fixtureURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        do {
            _ = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)
            XCTFail("Expected API error")
        } catch {
            XCTAssertEqual(error as? OpenAIClientError, .api(message: "Unsupported audio format"))
            XCTAssertFalse(error.localizedDescription.contains("Authorization"))
            XCTAssertFalse(error.localizedDescription.contains("unit-test-key"))
        }
        let requests = await session.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testCancellationMapsToCancellationErrorWithoutRetry() async throws {
        let session = RecordingURLSession([.failure(URLError(.cancelled))])
        let client = try makeClient(session: session)

        do {
            try await client.testConnection()
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = await session.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testOversizedAudioFailsBeforeURLSessionRuns() async throws {
        let session = RecordingURLSession([])
        let configuration = OpenAIConfiguration(maximumUploadBytes: 3)
        let client = try makeClient(session: session, configuration: configuration)
        let fixtureURL = try makeAudioFixture(data: Data([0, 1, 2, 3]))
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        do {
            _ = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)
            XCTFail("Expected upload limit error")
        } catch {
            XCTAssertEqual(error as? OpenAIClientError, .uploadTooLarge(maximumBytes: 3))
        }
        let requests = await session.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testMultipartOverheadCannotPushRequestPastUploadLimit() async throws {
        let session = RecordingURLSession([])
        let configuration = OpenAIConfiguration(maximumUploadBytes: 512)
        let client = try makeClient(session: session, configuration: configuration)
        let fixtureURL = try makeAudioFixture(data: Data(repeating: 1, count: 450))
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        do {
            _ = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)
            XCTFail("Expected the total request size to respect the upload limit")
        } catch {
            XCTAssertEqual(error as? OpenAIClientError, .uploadTooLarge(maximumBytes: 512))
        }
        let requests = await session.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testMalformedSuccessResponseMapsToSafeInvalidResponseError() async throws {
        let session = RecordingURLSession([.http(statusCode: 200, body: Data(#"{"unexpected":true}"#.utf8))])
        let client = try makeClient(session: session)

        do {
            try await client.testConnection()
        } catch {
            XCTFail("Connection test does not decode a response: \(error)")
        }

        let transformSession = RecordingURLSession([.http(statusCode: 200, body: Data(#"{"unexpected":true}"#.utf8))])
        let transformClient = try makeClient(session: transformSession)
        do {
            _ = try await transformClient.transform(text: "Hello", instructions: "Polish it.")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? OpenAIClientError, .invalidResponse)
        }
    }

    private func makeClient(
        session: RecordingURLSession,
        configuration: OpenAIConfiguration = OpenAIConfiguration(),
        sleep: @escaping OpenAIClient.Sleep = { _ in }
    ) throws -> OpenAIClient {
        let store: any SecureStore = InMemorySecureStore()
        try store.saveOpenAIKey("unit-test-key")
        return OpenAIClient(
            configuration: configuration,
            secureStore: store,
            session: session,
            retryPolicy: RetryPolicy(),
            jitter: { 0 },
            sleep: sleep
        )
    }

    private func makeAudioFixture(
        data: Data = Data([0, 1, 2]),
        extension fileExtension: String = "m4a"
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperOpenAITest-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private actor DelayRecorder {
    private var recordedValues: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        recordedValues.append(value)
    }

    func values() -> [TimeInterval] {
        recordedValues
    }
}

private actor RecordingURLSession: URLSessionProtocol {
    enum Stub: Sendable {
        case http(statusCode: Int, body: Data)
        case failure(URLError)
    }

    private var stubs: [Stub]
    private var recordedRequests: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        guard !stubs.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        let stub = stubs.removeFirst()
        switch stub {
        case let .http(statusCode, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}
