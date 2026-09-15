import Foundation
import XCTest
@testable import Whisper

final class MeetingProcessingCoordinatorTests: XCTestCase {
    @MainActor
    func testStartPersistsInstructionSnapshotBeforeCaptureAndBlocksDictation() async throws {
        let fixture = try Fixture()

        let id = try await fixture.coordinator.start(
            title: "Design call",
            instructions: "Original instructions",
            resultLanguage: "Russian",
            microphoneDeviceID: "mic-1"
        )

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .recording)
        XCTAssertEqual(meeting.instructionsSnapshot, "Original instructions")
        XCTAssertEqual(meeting.resultLanguage, "Russian")
        let configuration = await fixture.recorder.startedConfiguration
        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertEqual(configuration?.meetingID, id)
        XCTAssertEqual(configuration?.microphoneDeviceID, "mic-1")
        XCTAssertTrue(blocksDictation)
        let events = fixture.events.values
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "history.create.recording")),
                          try XCTUnwrap(events.firstIndex(of: "recorder.start")))
    }

    @MainActor
    func testStopPersistsCaptureBeforeNetworkAndProducesReadyResult() async throws {
        let fixture = try Fixture()
        let stateLog = MeetingRuntimeStateLog()
        let stream = await fixture.coordinator.states()
        let stateTask = Task {
            for await state in stream {
                await stateLog.append(state)
                if case .ready = state { return }
            }
        }
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Summarize decisions",
            resultLanguage: "English"
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)
        await stateTask.value

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .ready)
        XCTAssertEqual(meeting.microphoneRelativePath, "meeting-\(id.uuidString)/microphone.m4a")
        XCTAssertEqual(meeting.systemAudioRelativePath, "meeting-\(id.uuidString)/system.m4a")
        XCTAssertEqual(meeting.microphoneStartOffset, 0.25)
        XCTAssertEqual(meeting.systemAudioStartOffset, 0.5)
        XCTAssertEqual(meeting.processedText, "Processed result")
        XCTAssertEqual(fixture.history.segmentValues(meetingID: id).map(\.text), ["Hello"])
        let transformInstructions = await fixture.transformer.instructions
        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertEqual(transformInstructions, [
            "Summarize decisions\n\nWrite the result in English."
        ])
        let events = fixture.events.values
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "history.status.captured")),
                          try XCTUnwrap(events.firstIndex(of: "transcriber.start")))
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "history.segments")),
                          try XCTUnwrap(events.firstIndex(of: "transformer.start")))
        XCTAssertFalse(blocksDictation)
        let runtimeStates = await stateLog.values
        XCTAssertTrue(runtimeStates.contains(.recording(meetingID: id)))
        XCTAssertTrue(runtimeStates.contains(.finalizing(meetingID: id)))
        XCTAssertTrue(runtimeStates.contains(.transcribing(meetingID: id, completed: 1, total: 1)))
        XCTAssertTrue(runtimeStates.contains(.processing(meetingID: id)))
        XCTAssertTrue(runtimeStates.contains(.ready(meetingID: id)))
    }

    @MainActor
    func testProcessingNetworkFailureRetriesOnlyTransform() async throws {
        let fixture = try Fixture(transformFailures: [URLError(.notConnectedToInternet)])
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Stable snapshot",
            resultLanguage: nil
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)

        var meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .captured)
        XCTAssertEqual(meeting.failureKind, .network)
        XCTAssertEqual(meeting.retryStage, .processing)
        XCTAssertEqual(fixture.history.segmentValues(meetingID: id).count, 1)
        let transcriberCallsBeforeRetry = await fixture.transcriber.callCount
        XCTAssertEqual(transcriberCallsBeforeRetry, 1)

        try await fixture.coordinator.retry(meetingID: id)

        meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .ready)
        let transcriberCallsAfterRetry = await fixture.transcriber.callCount
        let transformerCalls = await fixture.transformer.callCount
        let instructions = await fixture.transformer.instructions
        XCTAssertEqual(transcriberCallsAfterRetry, 1)
        XCTAssertEqual(transformerCalls, 2)
        XCTAssertEqual(instructions, ["Stable snapshot", "Stable snapshot"])
    }

    @MainActor
    func testTranscriptionRetryAndRepeatedReprocessReplaceDurableResultsWithoutDuplicates() async throws {
        let fixture = try Fixture(transcriptionFailures: [URLError(.notConnectedToInternet)])
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Stable snapshot",
            resultLanguage: nil
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)
        XCTAssertEqual(fixture.history.segmentValues(meetingID: id), [])

        try await fixture.coordinator.retry(meetingID: id)
        try await fixture.coordinator.reprocess(meetingID: id)
        try await fixture.coordinator.reprocess(meetingID: id)

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        let segments = fixture.history.segmentValues(meetingID: id)
        let transcriberCalls = await fixture.transcriber.callCount
        let transformerCalls = await fixture.transformer.callCount
        XCTAssertEqual(meeting.status, .ready)
        XCTAssertEqual(meeting.processedText, "Processed result")
        XCTAssertEqual(segments.map(\.text), ["Hello"])
        XCTAssertEqual(transcriberCalls, 2)
        XCTAssertEqual(transformerCalls, 3)
    }

    @MainActor
    func testInvalidKeyIsNotRetryableAndPreservesAudioAndTranscript() async throws {
        let fixture = try Fixture(transformFailures: [FeatureError.invalidAPIKey])
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Keep this",
            resultLanguage: nil
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .failed)
        XCTAssertEqual(meeting.failureKind, .authentication)
        XCTAssertFalse(meeting.failureKind?.isRetryable ?? true)
        XCTAssertFalse(meeting.microphoneRelativePath.isEmpty)
        XCTAssertFalse(meeting.systemAudioRelativePath.isEmpty)
        XCTAssertEqual(fixture.history.segmentValues(meetingID: id).map(\.text), ["Hello"])
        do {
            try await fixture.coordinator.retry(meetingID: id)
            XCTFail("Expected retry to be rejected")
        } catch {
            XCTAssertEqual(error as? MeetingProcessingError, .notRetryable)
        }
    }

    @MainActor
    func testMissingKeyDuringTranscriptionKeepsCaptureRetryable() async throws {
        let fixture = try Fixture(transcriptionFailures: [FeatureError.missingAPIKey])
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Keep this",
            resultLanguage: nil
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .captured)
        XCTAssertEqual(meeting.failureKind, .missingAPIKey)
        XCTAssertEqual(meeting.retryStage, .transcription)
        XCTAssertTrue(meeting.failureKind?.isRetryable == true)
        XCTAssertFalse(meeting.microphoneRelativePath.isEmpty)
        XCTAssertFalse(meeting.systemAudioRelativePath.isEmpty)
    }

    @MainActor
    func testStaleManualStopCompletionCannotTerminateNextMeeting() async throws {
        let fixture = try Fixture()
        let firstID = try await fixture.coordinator.start(
            title: "First",
            instructions: "Summarize",
            resultLanguage: nil
        )
        try? await Task.sleep(for: .milliseconds(20))
        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: firstID)
        await fixture.recorder.replayLastCompletion()

        let secondID = try await fixture.coordinator.start(
            title: "Second",
            instructions: "Summarize",
            resultLanguage: nil
        )
        try? await Task.sleep(for: .milliseconds(20))

        let second = try XCTUnwrap(fixture.history.meetingValue(id: secondID))
        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertEqual(second.status, .recording)
        XCTAssertTrue(blocksDictation)
    }

    @MainActor
    func testFinalizingPersistenceFailureAllowsStopToBeRetried() async throws {
        let fixture = try Fixture()
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Summarize",
            resultLanguage: nil
        )
        fixture.history.failNextStatusUpdate(.finalizing)

        do {
            try await fixture.coordinator.stop()
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error as? PersistenceError, .meetingNotFound)
        }

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)
        XCTAssertEqual(fixture.history.meetingValue(id: id)?.status, .ready)
    }

    @MainActor
    func testPartialCapturePersistenceFailureReleasesFinishedRecording() async throws {
        let fixture = try Fixture(failsWithPartialCapture: true)
        _ = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Summarize",
            resultLanguage: nil
        )
        fixture.history.failNextCaptureUpdate()

        do {
            try await fixture.coordinator.stop()
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error as? PersistenceError, .meetingNotFound)
        }

        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertFalse(blocksDictation)
        _ = try await fixture.coordinator.start(
            title: "Next",
            instructions: "Summarize",
            resultLanguage: nil
        )
    }

    @MainActor
    func testCancelDeletesDraftAndUnblocksDictation() async throws {
        let fixture = try Fixture()
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Summarize",
            resultLanguage: nil
        )

        let cancelled = await fixture.coordinator.cancel()
        let blocksDictation = await fixture.coordinator.blocksDictation()
        let cancelCount = await fixture.recorder.cancelCount
        let state = await fixture.coordinator.currentState()

        XCTAssertTrue(cancelled)
        XCTAssertNil(fixture.history.meetingValue(id: id))
        XCTAssertFalse(blocksDictation)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(state, .idle)
    }

    @MainActor
    func testAutomaticCompletionStillWorksAfterCancellingPreviousRecording() async throws {
        let fixture = try Fixture()
        _ = try await fixture.coordinator.start(
            title: "Cancelled",
            instructions: "Summarize",
            resultLanguage: nil
        )
        let cancelled = await fixture.coordinator.cancel()
        XCTAssertTrue(cancelled)

        let secondID = try await fixture.coordinator.start(
            title: "Completed automatically",
            instructions: "Summarize",
            resultLanguage: nil
        )
        await fixture.recorder.emitAutomaticCompletion()
        await fixture.coordinator.waitForProcessing(meetingID: secondID)

        let transcriberCalls = await fixture.transcriber.callCount
        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertEqual(fixture.history.meetingValue(id: secondID)?.status, .ready)
        XCTAssertEqual(transcriberCalls, 1)
        XCTAssertFalse(blocksDictation)
    }

    @MainActor
    func testAutomaticRecorderCompletionPersistsCaptureAndLaunchesProcessing() async throws {
        let fixture = try Fixture()
        let id = try await fixture.coordinator.start(
            title: "Three-hour call",
            instructions: "Summarize",
            resultLanguage: nil
        )

        await fixture.recorder.emitAutomaticCompletion()
        await fixture.coordinator.waitForProcessing(meetingID: id)

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        let transcriberCalls = await fixture.transcriber.callCount
        XCTAssertEqual(meeting.status, .ready)
        XCTAssertFalse(meeting.microphoneRelativePath.isEmpty)
        XCTAssertEqual(transcriberCalls, 1)
    }

    @MainActor
    func testExhaustedTransientAPIErrorRemainsRetryable() async throws {
        let fixture = try Fixture(
            transformFailures: [OpenAIClientError.transientAPI]
        )
        let id = try await fixture.coordinator.start(
            title: "Call",
            instructions: "Summarize",
            resultLanguage: nil
        )

        try await fixture.coordinator.stop()
        await fixture.coordinator.waitForProcessing(meetingID: id)

        let meeting = try XCTUnwrap(fixture.history.meetingValue(id: id))
        XCTAssertEqual(meeting.status, .captured)
        XCTAssertEqual(meeting.failureKind, .network)
        XCTAssertTrue(meeting.failureKind?.isRetryable == true)
    }

    @MainActor
    func testRecoveryMarksInterruptedCaptureAndResumesDurableStages() async throws {
        let fixture = try Fixture()
        let interruptedID = UUID()
        let capturedID = UUID()
        let processingID = UUID()
        fixture.history.insert(draft(id: interruptedID, status: .recording))
        fixture.history.insert(draft(id: capturedID, status: .captured))
        fixture.history.insert(draft(id: processingID, status: .processing))
        fixture.history.setSegments([
            TranscriptSegment(
                meetingID: processingID,
                source: .others,
                startTime: 0,
                endTime: 1,
                text: "Persisted"
            )
        ], meetingID: processingID)
        let recovery = MeetingRecoveryService(
            history: fixture.history,
            coordinator: fixture.coordinator,
            processingAvailable: { true }
        )

        try await recovery.resumeIncompleteJobs()

        XCTAssertEqual(fixture.history.meetingValue(id: interruptedID)?.status, .failed)
        XCTAssertEqual(fixture.history.meetingValue(id: interruptedID)?.failureKind, .interruptedCapture)
        XCTAssertEqual(fixture.history.meetingValue(id: capturedID)?.status, .ready)
        XCTAssertEqual(fixture.history.meetingValue(id: processingID)?.status, .ready)
        let transcriberCalls = await fixture.transcriber.callCount
        let transformerCalls = await fixture.transformer.callCount
        XCTAssertEqual(transcriberCalls, 1)
        XCTAssertEqual(transformerCalls, 2)
    }

    @MainActor
    func testRecoveryDoesNotInterruptRecordingOwnedByRunningCoordinator() async throws {
        let fixture = try Fixture()
        let id = try await fixture.coordinator.start(
            title: "Live call",
            instructions: "Summarize",
            resultLanguage: nil
        )
        let recovery = MeetingRecoveryService(
            history: fixture.history,
            coordinator: fixture.coordinator,
            processingAvailable: { true }
        )

        try await recovery.resumeIncompleteJobs()

        let runtimeState = await fixture.coordinator.currentState()
        let blocksDictation = await fixture.coordinator.blocksDictation()
        XCTAssertEqual(fixture.history.meetingValue(id: id)?.status, .recording)
        XCTAssertEqual(runtimeState, .recording(meetingID: id))
        XCTAssertTrue(blocksDictation)
    }

    @MainActor
    func testRecoveryLeavesCapturedJobPendingWhenProcessingUnavailable() async throws {
        let fixture = try Fixture()
        let id = UUID()
        fixture.history.insert(draft(id: id, status: .captured))
        let recovery = MeetingRecoveryService(
            history: fixture.history,
            coordinator: fixture.coordinator,
            processingAvailable: { false }
        )

        try await recovery.resumeIncompleteJobs()

        XCTAssertEqual(fixture.history.meetingValue(id: id)?.status, .captured)
        let transcriberCalls = await fixture.transcriber.callCount
        let transformerCalls = await fixture.transformer.callCount
        XCTAssertEqual(transcriberCalls, 0)
        XCTAssertEqual(transformerCalls, 0)
    }

    private func draft(id: UUID, status: MeetingStatus) -> MeetingDraft {
        MeetingDraft(
            id: id,
            title: "Recovered",
            status: status,
            instructionsSnapshot: "Original",
            microphoneRelativePath: "meeting-\(id.uuidString)/microphone.m4a",
            systemAudioRelativePath: "meeting-\(id.uuidString)/system.m4a"
        )
    }
}

private actor MeetingRuntimeStateLog {
    private(set) var values: [MeetingRuntimeState] = []
    func append(_ value: MeetingRuntimeState) { values.append(value) }
}

@MainActor
private struct Fixture {
    let root: URL
    let paths: AppPaths
    let events: EventLog
    let history: FakeMeetingJobStore
    let recorder: FakeMeetingRecorder
    let transcriber: FakeMeetingTranscriber
    let transformer: FakeMeetingTransformer
    let coordinator: MeetingProcessingCoordinator

    init(
        transcriptionFailures: [Error] = [],
        transformFailures: [Error] = [],
        failsWithPartialCapture: Bool = false
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperMeetingProcessingTests-\(UUID().uuidString)", isDirectory: true)
        self.root = root
        paths = try AppPaths(rootURL: root)
        events = EventLog()
        history = FakeMeetingJobStore(events: events)
        recorder = FakeMeetingRecorder(
            paths: paths,
            events: events,
            failsWithPartialCapture: failsWithPartialCapture
        )
        transcriber = FakeMeetingTranscriber(events: events, failures: transcriptionFailures)
        transformer = FakeMeetingTransformer(events: events, failures: transformFailures)
        coordinator = MeetingProcessingCoordinator(
            recorder: recorder,
            transcriber: transcriber,
            transformer: transformer,
            history: history,
            paths: paths,
            now: { Date(timeIntervalSinceReferenceDate: 100) }
        )
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []
    var values: [String] { lock.withLock { storedValues } }
    func append(_ value: String) { lock.withLock { storedValues.append(value) } }
}

@MainActor
private final class FakeMeetingJobStore: MeetingJobStore {
    private let events: EventLog
    private var meetings: [UUID: MeetingSnapshot] = [:]
    private var segments: [UUID: [TranscriptSegment]] = [:]
    private var failingStatus: MeetingStatus?
    private var captureUpdateShouldFail = false

    init(events: EventLog) { self.events = events }

    func createMeeting(_ draft: MeetingDraft) throws -> UUID {
        meetings[draft.id] = snapshot(draft)
        events.append("history.create.\(draft.status.rawValue)")
        return draft.id
    }

    func updateMeeting(id: UUID, mutation: MeetingMutation) throws {
        if case let .status(status, _) = mutation, failingStatus == status {
            failingStatus = nil
            throw PersistenceError.meetingNotFound
        }
        if case .capture = mutation, captureUpdateShouldFail {
            captureUpdateShouldFail = false
            throw PersistenceError.meetingNotFound
        }
        guard let current = meetings[id] else { throw PersistenceError.meetingNotFound }
        meetings[id] = applying(mutation, to: current)
        if case let .status(status, _) = mutation {
            events.append("history.status.\(status.rawValue)")
        }
    }

    func replaceSegments(meetingID: UUID, segments: [TranscriptSegment]) throws {
        self.segments[meetingID] = segments
        events.append("history.segments")
    }

    func meeting(id: UUID) throws -> MeetingSnapshot? { meetings[id] }
    func transcriptSegments(meetingID: UUID) throws -> [TranscriptSegment] {
        segments[meetingID] ?? []
    }
    func incompleteMeetings() throws -> [MeetingSnapshot] {
        meetings.values.filter { $0.status.isIncomplete }.sorted { $0.startedAt < $1.startedAt }
    }

    func deleteMeeting(id: UUID) throws {
        guard meetings.removeValue(forKey: id) != nil else {
            throw PersistenceError.meetingNotFound
        }
        segments[id] = nil
    }

    func insert(_ draft: MeetingDraft) { meetings[draft.id] = snapshot(draft) }
    func setSegments(_ value: [TranscriptSegment], meetingID: UUID) { segments[meetingID] = value }
    func meetingValue(id: UUID) -> MeetingSnapshot? { meetings[id] }
    func segmentValues(meetingID: UUID) -> [TranscriptSegment] { segments[meetingID] ?? [] }
    func failNextStatusUpdate(_ status: MeetingStatus) { failingStatus = status }
    func failNextCaptureUpdate() { captureUpdateShouldFail = true }

    private func snapshot(_ draft: MeetingDraft) -> MeetingSnapshot {
        MeetingSnapshot(
            id: draft.id,
            title: draft.title,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            duration: draft.duration,
            status: draft.status,
            progressCompleted: draft.progressCompleted,
            progressTotal: draft.progressTotal,
            instructionsSnapshot: draft.instructionsSnapshot,
            resultLanguage: draft.resultLanguage,
            microphoneRelativePath: draft.microphoneRelativePath,
            systemAudioRelativePath: draft.systemAudioRelativePath,
            microphoneStartOffset: draft.microphoneStartOffset,
            systemAudioStartOffset: draft.systemAudioStartOffset,
            processedText: draft.processedText,
            errorMessage: draft.errorMessage,
            failureKind: draft.failureKind,
            retryStage: draft.retryStage
        )
    }

    private func applying(_ mutation: MeetingMutation, to value: MeetingSnapshot) -> MeetingSnapshot {
        var title = value.title
        var endedAt = value.endedAt
        var duration = value.duration
        var status = value.status
        var progressCompleted = value.progressCompleted
        var progressTotal = value.progressTotal
        var microphonePath = value.microphoneRelativePath
        var systemPath = value.systemAudioRelativePath
        var microphoneOffset = value.microphoneStartOffset
        var systemOffset = value.systemAudioStartOffset
        var processedText = value.processedText
        var resultLanguage = value.resultLanguage
        var errorMessage = value.errorMessage
        var failureKind = value.failureKind
        var retryStage = value.retryStage
        switch mutation {
        case let .title(newTitle): title = newTitle
        case let .status(newStatus, message):
            status = newStatus; errorMessage = message; failureKind = nil; retryStage = nil
        case let .retryable(message, kind, stage):
            status = .captured; errorMessage = message; failureKind = kind; retryStage = stage
        case let .failure(message, kind, stage):
            status = .failed; errorMessage = message; failureKind = kind; retryStage = stage
        case let .progress(completed, total):
            progressCompleted = completed; progressTotal = total
        case let .capture(end, capturedDuration, microphone, system, micOffset, sysOffset):
            endedAt = end; duration = capturedDuration; microphonePath = microphone; systemPath = system
            microphoneOffset = micOffset; systemOffset = sysOffset
        case let .result(text, language): processedText = text; resultLanguage = language
        }
        return MeetingSnapshot(
            id: value.id, title: title, startedAt: value.startedAt, endedAt: endedAt,
            duration: duration, status: status, progressCompleted: progressCompleted,
            progressTotal: progressTotal, instructionsSnapshot: value.instructionsSnapshot,
            resultLanguage: resultLanguage, microphoneRelativePath: microphonePath,
            systemAudioRelativePath: systemPath, microphoneStartOffset: microphoneOffset,
            systemAudioStartOffset: systemOffset, processedText: processedText,
            errorMessage: errorMessage, failureKind: failureKind, retryStage: retryStage
        )
    }
}

private actor FakeMeetingRecorder: MeetingRecorder {
    private let paths: AppPaths
    private let events: EventLog
    private let failsWithPartialCapture: Bool
    private(set) var startedConfiguration: MeetingCaptureConfiguration?
    private let completionStream: AsyncStream<MeetingCaptureCompletion>
    private let completionContinuation: AsyncStream<MeetingCaptureCompletion>.Continuation
    private var lastCapture: CapturedMeeting?
    private var nextSubscriptionCompletion: MeetingCaptureCompletion?
    private(set) var cancelCount = 0

    init(paths: AppPaths, events: EventLog, failsWithPartialCapture: Bool) {
        self.paths = paths
        self.events = events
        self.failsWithPartialCapture = failsWithPartialCapture
        let completions = AsyncStream<MeetingCaptureCompletion>.makeStream()
        completionStream = completions.stream
        completionContinuation = completions.continuation
    }

    func start(configuration: MeetingCaptureConfiguration) async throws {
        startedConfiguration = configuration
        events.append("recorder.start")
    }

    func levels() -> AsyncStream<MeetingAudioLevels> { AsyncStream { $0.finish() } }
    func completions() -> AsyncStream<MeetingCaptureCompletion> {
        guard let completion = nextSubscriptionCompletion else { return completionStream }
        nextSubscriptionCompletion = nil
        return AsyncStream { continuation in
            continuation.yield(completion)
            continuation.finish()
        }
    }

    func stop() async throws -> CapturedMeeting {
        let id = try XCTUnwrap(startedConfiguration?.meetingID)
        let directory = try paths.recordingDirectory(for: id)
        let microphone = directory.appendingPathComponent("microphone.m4a")
        let system = directory.appendingPathComponent("system.m4a")
        try Data([1]).write(to: microphone)
        try Data([2]).write(to: system)
        let capture = CapturedMeeting(
            microphoneURL: microphone,
            systemAudioURL: system,
            microphoneStartOffset: 0.25,
            systemAudioStartOffset: 0.5,
            startedAt: Date(timeIntervalSinceReferenceDate: 90),
            endedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        lastCapture = capture
        if failsWithPartialCapture {
            let failure = MeetingCaptureFailure(
                unavailableSource: .systemAudio,
                microphoneURL: microphone,
                systemAudioURL: nil,
                microphoneStartOffset: capture.microphoneStartOffset,
                systemAudioStartOffset: capture.systemAudioStartOffset,
                startedAt: capture.startedAt,
                endedAt: capture.endedAt
            )
            completionContinuation.yield(.failed(meetingID: id, failure: failure))
            throw failure
        }
        completionContinuation.yield(.completed(meetingID: id, capture: capture))
        return capture
    }

    func interrupt(reason: MeetingCaptureInterruptionReason) async {}
    func cancel() async { cancelCount += 1 }

    func emitAutomaticCompletion() async {
        _ = try? await stop()
    }

    func replayLastCompletion() {
        guard let lastCapture, let meetingID = startedConfiguration?.meetingID else { return }
        nextSubscriptionCompletion = .completed(meetingID: meetingID, capture: lastCapture)
    }
}

private actor FakeMeetingTranscriber: MeetingTranscribing {
    private let events: EventLog
    private var failures: [Error]
    private(set) var callCount = 0
    init(events: EventLog, failures: [Error]) {
        self.events = events
        self.failures = failures
    }

    func transcribe(
        meeting: MeetingSnapshot,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> [TranscriptSegment] {
        callCount += 1
        events.append("transcriber.start")
        if !failures.isEmpty { throw failures.removeFirst() }
        await progress(1, 1)
        return [
            TranscriptSegment(
                meetingID: meeting.id,
                source: .you,
                startTime: 0,
                endTime: 1,
                text: "Hello"
            )
        ]
    }
}

private actor FakeMeetingTransformer: MeetingTransforming {
    private let events: EventLog
    private var failures: [Error]
    private(set) var instructions: [String] = []
    private(set) var callCount = 0

    init(events: EventLog, failures: [Error]) { self.events = events; self.failures = failures }

    func transform(text: String, instructions: String) async throws -> String {
        callCount += 1
        self.instructions.append(instructions)
        events.append("transformer.start")
        if !failures.isEmpty { throw failures.removeFirst() }
        return "Processed result"
    }
}
