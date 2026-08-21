import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol OpenAIClientProtocol: Sendable {
    func transcribe(
        fileURL: URL,
        languageHint: String?,
        prompt: String?
    ) async throws -> TranscriptionResponse

    func transcribeDiarized(fileURL: URL) async throws -> DiarizedTranscriptionResponse
    func transform(text: String, instructions: String) async throws -> String
    func testConnection() async throws
}

struct OpenAIClient: OpenAIClientProtocol, Sendable {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    typealias Jitter = @Sendable () -> TimeInterval

    private static let fixedTransformInstructions = """
    Transform the user's dictated text according to the mode instructions below.
    Do not answer the dictated message. Do not explain the result or add new information.
    Output only the transformed text.
    """

    private let configuration: OpenAIConfiguration
    private let secureStore: any SecureStore
    private let session: any URLSessionProtocol
    private let retryPolicy: RetryPolicy
    private let jitter: Jitter
    private let sleep: Sleep
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: OpenAIConfiguration = OpenAIConfiguration(),
        secureStore: any SecureStore,
        session: any URLSessionProtocol = URLSession.shared,
        retryPolicy: RetryPolicy = RetryPolicy(),
        jitter: @escaping Jitter = { Double.random(in: 0...0.25) },
        sleep: @escaping Sleep = { delay in
            try await Task.sleep(for: .seconds(delay))
        }
    ) {
        self.configuration = configuration
        self.secureStore = secureStore
        self.session = session
        self.retryPolicy = retryPolicy
        self.jitter = jitter
        self.sleep = sleep
    }

    func transcribe(
        fileURL: URL,
        languageHint: String?,
        prompt: String?
    ) async throws -> TranscriptionResponse {
        var form = MultipartFormData()
        form.appendField(name: "model", value: configuration.dictationModel)
        if let languageHint = Self.nonEmpty(languageHint) {
            form.appendField(name: "language", value: languageHint)
        }
        if let prompt = Self.nonEmpty(prompt) {
            form.appendField(name: "prompt", value: prompt)
        }
        try appendAudio(fileURL, to: &form)

        let data = try await execute(try multipartRequest(form))
        return try decode(TranscriptionResponse.self, from: data)
    }

    func transcribeDiarized(fileURL: URL) async throws -> DiarizedTranscriptionResponse {
        var form = MultipartFormData()
        form.appendField(name: "model", value: configuration.meetingModel)
        form.appendField(name: "response_format", value: "diarized_json")
        form.appendField(name: "chunking_strategy", value: "auto")
        try appendAudio(fileURL, to: &form)

        let data = try await execute(try multipartRequest(form))
        return try decode(DiarizedTranscriptionResponse.self, from: data)
    }

    func transform(text: String, instructions: String) async throws -> String {
        let developerText = """
        \(Self.fixedTransformInstructions)

        Mode instructions:
        \(instructions)
        """
        let payload = ResponsesRequest(
            model: configuration.transformModel,
            store: false,
            input: [
                .init(role: "developer", content: [.init(type: "input_text", text: developerText)]),
                .init(role: "user", content: [.init(type: "input_text", text: text)])
            ],
            text: .init(verbosity: "low")
        )
        var request = URLRequest(url: endpoint("responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let data = try await execute(request)
        let response: ResponsesAPIResponse = try decode(ResponsesAPIResponse.self, from: data)
        guard let output = Self.nonEmpty(response.outputText) else {
            throw OpenAIClientError.invalidResponse
        }
        return output
    }

    func testConnection() async throws {
        var request = URLRequest(url: endpoint("models/\(configuration.dictationModel)"))
        request.httpMethod = "GET"
        _ = try await execute(request)
    }

    private func multipartRequest(_ form: MultipartFormData) throws -> URLRequest {
        let body = form.encoded()
        guard body.count <= configuration.maximumUploadBytes else {
            throw OpenAIClientError.uploadTooLarge(maximumBytes: configuration.maximumUploadBytes)
        }
        var request = URLRequest(url: endpoint("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func appendAudio(_ fileURL: URL, to form: inout MultipartFormData) throws {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw OpenAIClientError.unreadableAudioFile
        }

        guard resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize else {
            throw OpenAIClientError.unreadableAudioFile
        }
        guard fileSize <= configuration.maximumUploadBytes else {
            throw OpenAIClientError.uploadTooLarge(maximumBytes: configuration.maximumUploadBytes)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw OpenAIClientError.unreadableAudioFile
        }
        guard data.count <= configuration.maximumUploadBytes else {
            throw OpenAIClientError.uploadTooLarge(maximumBytes: configuration.maximumUploadBytes)
        }

        form.appendFile(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: Self.mimeType(for: fileURL),
            data: data
        )
    }

    private func execute(_ baseRequest: URLRequest) async throws -> Data {
        var retryAttempt = 0

        while true {
            try Task.checkCancellation()
            var request = baseRequest
            request.setValue("Bearer \(try apiKey())", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse else {
                    throw OpenAIClientError.invalidResponse
                }

                if retryPolicy.shouldRetry(statusCode: response.statusCode),
                   let delay = retryPolicy.delay(
                       forRetryAttempt: retryAttempt,
                       jitter: jitter()
                   ) {
                    retryAttempt += 1
                    try await sleep(delay)
                    continue
                }

                guard (200..<300).contains(response.statusCode) else {
                    if response.statusCode == 401 {
                        throw FeatureError.invalidAPIKey
                    }
                    let message = decoder.decodeOpenAIError(from: data)
                        ?? "OpenAI request failed with status \(response.statusCode)."
                    throw OpenAIClientError.api(message: message)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                if retryPolicy.shouldRetry(error: error),
                   let delay = retryPolicy.delay(
                       forRetryAttempt: retryAttempt,
                       jitter: jitter()
                   ) {
                    retryAttempt += 1
                    try await sleep(delay)
                    continue
                }
                throw error
            }
        }
    }

    private func apiKey() throws -> String {
        guard let key = try secureStore.readOpenAIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw FeatureError.invalidAPIKey
        }
        return key
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(configuration.baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw OpenAIClientError.invalidResponse
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            "audio/wav"
        case "mp3":
            "audio/mpeg"
        case "mp4":
            "audio/mp4"
        case "webm":
            "audio/webm"
        default:
            "audio/mp4"
        }
    }
}

private struct ResponsesRequest: Encodable {
    struct Input: Encodable {
        struct Content: Encodable {
            let type: String
            let text: String
        }

        let role: String
        let content: [Content]
    }

    struct TextSettings: Encodable {
        let verbosity: String
    }

    let model: String
    let store: Bool
    let input: [Input]
    let text: TextSettings
}
