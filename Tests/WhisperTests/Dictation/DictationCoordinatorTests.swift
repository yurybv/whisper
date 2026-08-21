import Foundation
import XCTest
@testable import Whisper

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    func testBeginCapturesModeAndTargetAndRejectsASecondSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin(deviceID: "studio-mic")

        let recordingState = await fixture.coordinator.currentState()
        XCTAssertEqual(recordingState, .recording(modeName: "Russian to English"))
        XCTAssertEqual(fixture.events.values, ["mode", "target", "recorder.start:studio-mic"])

        do {
            try await fixture.coordinator.begin()
            XCTFail("Expected a busy coordinator error")
        } catch {
            XCTAssertEqual(error as? DictationCoordinatorError, .busy)
        }
        let startCount = await fixture.recorder.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testFinishProcessesInOrderUsingModeSnapshotAndStoresResult() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin()
        fixture.modeProvider.mode = .defaultMode
        await fixture.coordinator.finish()

        XCTAssertEqual(
            fixture.events.values,
            ["mode", "target", "recorder.start", "recorder.stop", "transcribe", "transform", "insert", "history"]
        )
        let languageHint = await fixture.openAI.languageHint
        let transformedInput = await fixture.openAI.transformedInput
        let transformInstructions = await fixture.openAI.transformInstructions
        let insertedText = await fixture.insertion.insertedText
        XCTAssertEqual(languageHint, "ru")
        XCTAssertEqual(transformedInput, "Привет из транскрипции")
        XCTAssertTrue(transformInstructions?.contains("Translate Russian speech") == true)
        XCTAssertEqual(insertedText, "Natural English output")
        XCTAssertEqual(fixture.history.drafts.count, 1)

        let draft = try XCTUnwrap(fixture.history.drafts.first)
        XCTAssertEqual(draft.modeID, fixture.customMode.id)
        XCTAssertEqual(draft.modeNameSnapshot, fixture.customMode.name)
        XCTAssertEqual(draft.modeInstructionsSnapshot, fixture.customMode.instructions)
        XCTAssertEqual(draft.detectedLanguages, ["ru"])
        XCTAssertEqual(draft.originalText, "Привет из транскрипции")
        XCTAssertEqual(draft.outputText, "Natural English output")
        XCTAssertEqual(draft.targetApplicationBundleID, "com.apple.TextEdit")
        XCTAssertEqual(draft.status, .ready)
        let completedState = await fixture.coordinator.currentState()
        XCTAssertEqual(completedState, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audioURL.path))
    }

    func testSilentCaptureSkipsNetworkInsertionAndHistoryAndReturnsIdle() async throws {
        let fixture = try makeFixture(containsSpeech: false)
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin()
        await fixture.coordinator.finish()

        XCTAssertEqual(
            fixture.events.values,
            ["mode", "target", "recorder.start", "recorder.stop"]
        )
        XCTAssertEqual(fixture.history.drafts, [])
        let idleState = await fixture.coordinator.currentState()
        XCTAssertEqual(idleState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audioURL.path))
    }

    func testCancelDuringRecordingRemovesAudioAndStoresNoHistory() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin()
        await fixture.coordinator.cancel()

        let cancelCount = await fixture.recorder.cancelCount
        let idleState = await fixture.coordinator.currentState()
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(fixture.history.drafts, [])
        XCTAssertEqual(idleState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audioURL.path))
    }

    func testCancelWhileCapturingTargetInvalidatesPendingBegin() async throws {
        let gate = AsyncGate()
        let fixture = try makeFixture(targetCaptureGate: gate)
        defer { fixture.cleanup() }

        let beginTask = Task {
            try await fixture.coordinator.begin()
        }
        await waitUntil { fixture.events.values.contains("target") }

        await fixture.coordinator.cancel()
        await gate.open()

        do {
            try await beginTask.value
            XCTFail("Expected pending begin to be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let state = await fixture.coordinator.currentState()
        let startCount = await fixture.recorder.startCount
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(startCount, 0)
    }

    func testCancelWhileTranscribingPreventsTransformInsertionAndHistory() async throws {
        let gate = AsyncGate()
        let fixture = try makeFixture(transcriptionGate: gate)
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin()
        let finishTask = Task { await fixture.coordinator.finish() }
        await waitUntil { fixture.events.values.contains("transcribe") }

        await fixture.coordinator.cancel()
        await gate.open()
        await finishTask.value

        XCTAssertFalse(fixture.events.values.contains("transform"))
        XCTAssertFalse(fixture.events.values.contains("insert"))
        XCTAssertEqual(fixture.history.drafts, [])
        let idleState = await fixture.coordinator.currentState()
        XCTAssertEqual(idleState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.audioURL.path))
    }

    func testTranscriptionFailureRetainsAudioForRetryAndPublishesFailure() async throws {
        let fixture = try makeFixture(transcriptionError: TestFailure.transcription)
        defer { fixture.cleanup() }

        try await fixture.coordinator.begin()
        await fixture.coordinator.finish()

        let state = await fixture.coordinator.currentState()
        guard case let .failed(message, textOnClipboard) = state else {
            return XCTFail("Expected a failed state")
        }
        XCTAssertTrue(message.contains("Transcription failed"))
        XCTAssertFalse(textOnClipboard)
        let retryAudioURL = await fixture.coordinator.retryAudioURL()
        XCTAssertEqual(retryAudioURL, fixture.audioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.audioURL.path))
        XCTAssertEqual(fixture.history.drafts, [])
    }

    func testStateStreamEmitsEachSuccessfulTransition() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let stream = await fixture.coordinator.states()
        let collector = Task { () -> [DictationState] in
            var states: [DictationState] = []
            for await state in stream {
                states.append(state)
                if state == .completed { break }
            }
            return states
        }

        try await fixture.coordinator.begin()
        await fixture.coordinator.finish()

        let emittedStates = await collector.value
        XCTAssertEqual(
            emittedStates,
            [
                .idle,
                .recording(modeName: "Russian to English"),
                .transcribing,
                .transforming,
                .inserting,
                .completed
            ]
        )
    }

    private func makeFixture(
        containsSpeech: Bool = true,
        targetCaptureGate: AsyncGate? = nil,
        transcriptionGate: AsyncGate? = nil,
        transcriptionError: Error? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperDictationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("capture.wav")
        try Data("audio".utf8).write(to: audioURL)

        let events = EventLog()
        let customMode = ModeDefinition(
            name: "Russian to English",
            instructions: "Translate Russian speech into natural conversational English.",
            languageHint: "ru",
            isDefault: false,
            isEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let recorder = FakeMicrophoneRecorder(
            capture: CapturedAudio(
                fileURL: audioURL,
                duration: 2.5,
                peakLevel: 0.7,
                containsSpeech: containsSpeech
            ),
            events: events
        )
        let openAI = FakeOpenAIClient(
            events: events,
            transcriptionGate: transcriptionGate,
            transcriptionError: transcriptionError
        )
        let insertion = FakeTextInsertionService(events: events, captureGate: targetCaptureGate)
        let modeProvider = FakeActiveModeProvider(mode: customMode, events: events)
        let history = FakeDictationHistoryWriter(events: events)
        let coordinator = DictationCoordinator(
            recorder: recorder,
            openAI: openAI,
            modeProvider: modeProvider,
            history: history,
            insertion: insertion,
            now: { Date(timeIntervalSince1970: 100) }
        )
        return Fixture(
            coordinator: coordinator,
            recorder: recorder,
            openAI: openAI,
            insertion: insertion,
            modeProvider: modeProvider,
            history: history,
            events: events,
            customMode: customMode,
            audioURL: audioURL,
            directory: directory
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }
}

private struct Fixture {
    let coordinator: DictationCoordinator
    let recorder: FakeMicrophoneRecorder
    let openAI: FakeOpenAIClient
    let insertion: FakeTextInsertionService
    let modeProvider: FakeActiveModeProvider
    let history: FakeDictationHistoryWriter
    let events: EventLog
    let customMode: ModeDefinition
    let audioURL: URL
    let directory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private enum TestFailure: LocalizedError {
    case transcription

    var errorDescription: String? { "Transcription failed for test." }
}

private actor FakeMicrophoneRecorder: MicrophoneRecorder {
    private let capture: CapturedAudio
    private let events: EventLog
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    init(capture: CapturedAudio, events: EventLog) {
        self.capture = capture
        self.events = events
    }

    func start(deviceID: String?) {
        startCount += 1
        events.append(deviceID.map { "recorder.start:\($0)" } ?? "recorder.start")
    }

    func levels() -> AsyncStream<Float> { AsyncStream { $0.finish() } }

    func stop() -> CapturedAudio {
        events.append("recorder.stop")
        return capture
    }

    func cancel() {
        cancelCount += 1
        events.append("recorder.cancel")
        try? FileManager.default.removeItem(at: capture.fileURL)
    }
}

private actor FakeOpenAIClient: OpenAIClientProtocol {
    private let events: EventLog
    private let transcriptionGate: AsyncGate?
    private let transcriptionError: Error?
    private(set) var languageHint: String?
    private(set) var transformedInput: String?
    private(set) var transformInstructions: String?

    init(events: EventLog, transcriptionGate: AsyncGate?, transcriptionError: Error?) {
        self.events = events
        self.transcriptionGate = transcriptionGate
        self.transcriptionError = transcriptionError
    }

    func transcribe(fileURL: URL, languageHint: String?, prompt: String?) async throws -> TranscriptionResponse {
        events.append("transcribe")
        self.languageHint = languageHint
        await transcriptionGate?.wait()
        if let transcriptionError { throw transcriptionError }
        return TranscriptionResponse(
            text: "Привет из транскрипции",
            languages: [DetectedLanguage(language: "ru", probability: 0.99)]
        )
    }

    func transcribeDiarized(fileURL: URL) async throws -> DiarizedTranscriptionResponse {
        fatalError("Not used by dictation")
    }

    func transform(text: String, instructions: String) -> String {
        events.append("transform")
        transformedInput = text
        transformInstructions = instructions
        return "Natural English output"
    }

    func testConnection() {}
}

private actor FakeTextInsertionService: TextInsertionService {
    private let events: EventLog
    private let captureGate: AsyncGate?
    private(set) var insertedText: String?

    init(events: EventLog, captureGate: AsyncGate?) {
        self.events = events
        self.captureGate = captureGate
    }

    func captureFocusedTarget() async -> FocusedTarget {
        events.append("target")
        await captureGate?.wait()
        return FocusedTarget(
            processIdentifier: 123,
            bundleIdentifier: "com.apple.TextEdit",
            element: nil
        )
    }

    func insert(_ text: String, into target: FocusedTarget) -> InsertionResult {
        events.append("insert")
        insertedText = text
        return .insertedDirectly
    }
}

@MainActor
private final class FakeActiveModeProvider: ActiveModeProviding {
    var mode: ModeDefinition
    private let events: EventLog

    init(mode: ModeDefinition, events: EventLog) {
        self.mode = mode
        self.events = events
    }

    func activeMode() -> ModeDefinition {
        events.append("mode")
        return mode
    }
}

@MainActor
private final class FakeDictationHistoryWriter: DictationHistoryWriting {
    private(set) var drafts: [DictationDraft] = []
    private let events: EventLog

    init(events: EventLog) { self.events = events }

    func createDictation(_ draft: DictationDraft) -> UUID {
        events.append("history")
        drafts.append(draft)
        return draft.id
    }
}
