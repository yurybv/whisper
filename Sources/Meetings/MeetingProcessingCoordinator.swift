import Foundation

@MainActor
protocol MeetingJobStore: Sendable {
    @discardableResult
    func createMeeting(_ draft: MeetingDraft) throws -> UUID
    func updateMeeting(id: UUID, mutation: MeetingMutation) throws
    func replaceSegments(meetingID: UUID, segments: [TranscriptSegment]) throws
    func meeting(id: UUID) throws -> MeetingSnapshot?
    func transcriptSegments(meetingID: UUID) throws -> [TranscriptSegment]
    func incompleteMeetings() throws -> [MeetingSnapshot]
}

extension HistoryRepository: MeetingJobStore {}

protocol MeetingTranscribing: Sendable {
    func transcribe(
        meeting: MeetingSnapshot,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) async -> Void
    ) async throws -> [TranscriptSegment]
}

protocol MeetingTransforming: Sendable {
    func transform(text: String, instructions: String) async throws -> String
}

extension OpenAIClient: MeetingTransforming {}

enum MeetingProcessingError: Error, Sendable, Equatable {
    case busy
    case noActiveRecording
    case meetingNotFound
    case notRetryable
    case transcriptUnavailable
}

actor MeetingProcessingCoordinator {
    typealias Now = @Sendable () -> Date

    private enum ProcessingStage: Sendable {
        case transcription
        case processing
    }

    private let recorder: any MeetingRecorder
    private let transcriber: any MeetingTranscribing
    private let transformer: any MeetingTransforming
    private let history: any MeetingJobStore
    private let paths: AppPaths
    private let now: Now

    private var activeMeetingID: UUID?
    private var startAttemptID: UUID?
    private var terminalMeetingID: UUID?
    private var completionTask: Task<Void, Never>?
    private var processingTasks: [UUID: Task<Void, Never>] = [:]

    init(
        recorder: any MeetingRecorder,
        transcriber: any MeetingTranscribing,
        transformer: any MeetingTransforming,
        history: any MeetingJobStore,
        paths: AppPaths,
        now: @escaping Now = Date.init
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.transformer = transformer
        self.history = history
        self.paths = paths
        self.now = now
    }

    deinit {
        completionTask?.cancel()
        for task in processingTasks.values { task.cancel() }
    }

    @discardableResult
    func start(
        title: String,
        instructions: String,
        resultLanguage: String?,
        microphoneDeviceID: String? = nil
    ) async throws -> UUID {
        guard activeMeetingID == nil, startAttemptID == nil else {
            throw MeetingProcessingError.busy
        }
        let attemptID = UUID()
        startAttemptID = attemptID
        defer {
            if startAttemptID == attemptID { startAttemptID = nil }
        }

        let id = UUID()
        let draft = MeetingDraft(
            id: id,
            title: title,
            startedAt: now(),
            status: .recording,
            instructionsSnapshot: instructions,
            resultLanguage: Self.nonEmpty(resultLanguage)
        )
        _ = try await history.createMeeting(draft)
        do {
            try await recorder.start(
                configuration: MeetingCaptureConfiguration(
                    meetingID: id,
                    microphoneDeviceID: microphoneDeviceID
                )
            )
            guard startAttemptID == attemptID, activeMeetingID == nil else {
                await recorder.cancel()
                throw MeetingProcessingError.busy
            }
            activeMeetingID = id
            monitorRecorderCompletions(meetingID: id)
            return id
        } catch {
            try? await history.updateMeeting(
                id: id,
                mutation: .failure(
                    message: "Meeting capture could not start.",
                    kind: .capture,
                    stage: nil
                )
            )
            throw error
        }
    }

    func stop() async throws {
        guard let meetingID = activeMeetingID else {
            throw MeetingProcessingError.noActiveRecording
        }
        guard terminalMeetingID == nil else { throw MeetingProcessingError.busy }
        terminalMeetingID = meetingID
        do {
            try await history.updateMeeting(
                id: meetingID,
                mutation: .status(.finalizing, errorMessage: nil)
            )
        } catch {
            if terminalMeetingID == meetingID { terminalMeetingID = nil }
            throw error
        }
        do {
            let capture = try await recorder.stop()
            try await persistCapture(capture, meetingID: meetingID)
            finishCaptureLifecycle(meetingID: meetingID)
            launchProcessing(meetingID: meetingID, stage: .transcription)
        } catch let failure as MeetingCaptureFailure {
            defer { finishCaptureLifecycle(meetingID: meetingID) }
            try await persistCaptureFailure(failure, meetingID: meetingID)
            throw failure
        } catch {
            finishCaptureLifecycle(meetingID: meetingID)
            try? await history.updateMeeting(
                id: meetingID,
                mutation: .failure(
                    message: "Meeting capture could not be finalized. Available audio was preserved.",
                    kind: .capture,
                    stage: nil
                )
            )
            throw error
        }
    }

    func blocksDictation() -> Bool {
        activeMeetingID != nil || startAttemptID != nil || terminalMeetingID != nil
    }

    func waitForProcessing(meetingID: UUID) async {
        for _ in 0..<1_000 {
            if let task = processingTasks[meetingID] {
                await task.value
                return
            }
            if activeMeetingID != meetingID, terminalMeetingID != meetingID { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func resume(meetingID: UUID) async {
        do {
            guard let meeting = try await history.meeting(id: meetingID) else { return }
            switch meeting.status {
            case .recording, .finalizing:
                try await history.updateMeeting(
                    id: meetingID,
                    mutation: .failure(
                        message: "Whisper was closed before capture finished. Preserved files were not deleted.",
                        kind: .interruptedCapture,
                        stage: nil
                    )
                )
            case .captured:
                let stage: ProcessingStage = meeting.retryStage == .processing
                    ? .processing
                    : .transcription
                await launchAndWait(meetingID: meetingID, stage: stage)
            case .transcribing:
                await launchAndWait(meetingID: meetingID, stage: .transcription)
            case .processing:
                await launchAndWait(meetingID: meetingID, stage: .processing)
            case .ready, .failed:
                return
            }
        } catch {
            try? await persistFailure(error, meetingID: meetingID, stage: .transcription)
        }
    }

    func retry(meetingID: UUID) async throws {
        guard let meeting = try await history.meeting(id: meetingID) else {
            throw MeetingProcessingError.meetingNotFound
        }
        guard meeting.failureKind?.isRetryable == true,
              let retryStage = meeting.retryStage else {
            throw MeetingProcessingError.notRetryable
        }
        let stage: ProcessingStage = retryStage == .processing ? .processing : .transcription
        await launchAndWait(meetingID: meetingID, stage: stage)
    }

    func reprocess(meetingID: UUID) async throws {
        guard try await history.meeting(id: meetingID) != nil else {
            throw MeetingProcessingError.meetingNotFound
        }
        let segments = try await history.transcriptSegments(meetingID: meetingID)
        guard !segments.isEmpty else { throw MeetingProcessingError.transcriptUnavailable }
        await launchAndWait(meetingID: meetingID, stage: .processing)
    }

    private func monitorRecorderCompletions(meetingID: UUID) {
        completionTask?.cancel()
        completionTask = Task { [weak self, recorder] in
            let completions = await recorder.completions()
            for await completion in completions {
                guard !Task.isCancelled else { return }
                guard completion.meetingID == meetingID else { continue }
                await self?.handleRecorderCompletion(completion)
                return
            }
        }
    }

    private func handleRecorderCompletion(_ completion: MeetingCaptureCompletion) async {
        guard let meetingID = activeMeetingID, terminalMeetingID == nil else { return }
        terminalMeetingID = meetingID
        do {
            switch completion {
            case let .completed(_, capture):
                try await history.updateMeeting(
                    id: meetingID,
                    mutation: .status(.finalizing, errorMessage: nil)
                )
                try await persistCapture(capture, meetingID: meetingID)
                finishCaptureLifecycle(meetingID: meetingID)
                launchProcessing(meetingID: meetingID, stage: .transcription)
            case let .failed(_, failure):
                try await persistCaptureFailure(failure, meetingID: meetingID)
                finishCaptureLifecycle(meetingID: meetingID)
            }
        } catch {
            finishCaptureLifecycle(meetingID: meetingID)
            try? await history.updateMeeting(
                id: meetingID,
                mutation: .failure(
                    message: "Meeting capture could not be finalized. Available audio was preserved.",
                    kind: .capture,
                    stage: nil
                )
            )
        }
    }

    private func persistCapture(_ capture: CapturedMeeting, meetingID: UUID) async throws {
        try await history.updateMeeting(
            id: meetingID,
            mutation: .capture(
                endedAt: capture.endedAt,
                duration: max(0, capture.endedAt.timeIntervalSince(capture.startedAt)),
                microphoneRelativePath: try paths.relativeRecordingPath(
                    for: capture.microphoneURL,
                    meetingID: meetingID
                ),
                systemAudioRelativePath: try paths.relativeRecordingPath(
                    for: capture.systemAudioURL,
                    meetingID: meetingID
                ),
                microphoneStartOffset: capture.microphoneStartOffset,
                systemAudioStartOffset: capture.systemAudioStartOffset
            )
        )
        try await history.updateMeeting(
            id: meetingID,
            mutation: .status(.captured, errorMessage: nil)
        )
    }

    private func persistCaptureFailure(
        _ failure: MeetingCaptureFailure,
        meetingID: UUID
    ) async throws {
        try await history.updateMeeting(
            id: meetingID,
            mutation: .capture(
                endedAt: failure.endedAt,
                duration: max(0, failure.endedAt.timeIntervalSince(failure.startedAt)),
                microphoneRelativePath: try failure.microphoneURL.map {
                    try paths.relativeRecordingPath(for: $0, meetingID: meetingID)
                } ?? "",
                systemAudioRelativePath: try failure.systemAudioURL.map {
                    try paths.relativeRecordingPath(for: $0, meetingID: meetingID)
                } ?? "",
                microphoneStartOffset: failure.microphoneStartOffset,
                systemAudioStartOffset: failure.systemAudioStartOffset
            )
        )
        try await history.updateMeeting(
            id: meetingID,
            mutation: .failure(
                message: failure.localizedDescription,
                kind: .capture,
                stage: nil
            )
        )
    }

    private func finishCaptureLifecycle(meetingID: UUID) {
        if activeMeetingID == meetingID { activeMeetingID = nil }
        if terminalMeetingID == meetingID { terminalMeetingID = nil }
        completionTask?.cancel()
        completionTask = nil
    }

    private func launchProcessing(meetingID: UUID, stage: ProcessingStage) {
        guard processingTasks[meetingID] == nil else { return }
        let task = Task { [weak self] in
            await self?.runProcessing(meetingID: meetingID, stage: stage)
            await self?.processingFinished(meetingID: meetingID)
        }
        processingTasks[meetingID] = task
    }

    private func launchAndWait(meetingID: UUID, stage: ProcessingStage) async {
        launchProcessing(meetingID: meetingID, stage: stage)
        let task = processingTasks[meetingID]
        await task?.value
    }

    private func processingFinished(meetingID: UUID) {
        processingTasks[meetingID] = nil
    }

    private func runProcessing(meetingID: UUID, stage: ProcessingStage) async {
        do {
            guard let meeting = try await history.meeting(id: meetingID) else { return }
            switch stage {
            case .transcription:
                await transcribeAndProcess(meeting)
            case .processing:
                await processPersistedTranscript(meeting)
            }
        } catch {
            try? await persistFailure(
                error,
                meetingID: meetingID,
                stage: stage == .processing ? .processing : .transcription
            )
        }
    }

    private func transcribeAndProcess(_ meeting: MeetingSnapshot) async {
        do {
            try await history.updateMeeting(
                id: meeting.id,
                mutation: .status(.transcribing, errorMessage: nil)
            )
            let history = history
            let meetingID = meeting.id
            let segments = try await transcriber.transcribe(meeting: meeting) { completed, total in
                try? await history.updateMeeting(
                    id: meetingID,
                    mutation: .progress(completed: completed, total: total)
                )
            }
            try await history.replaceSegments(meetingID: meeting.id, segments: segments)
            await transform(meeting: meeting, segments: segments)
        } catch {
            try? await persistFailure(error, meetingID: meeting.id, stage: .transcription)
        }
    }

    private func processPersistedTranscript(_ meeting: MeetingSnapshot) async {
        do {
            let segments = try await history.transcriptSegments(meetingID: meeting.id)
            guard !segments.isEmpty else { throw MeetingProcessingError.transcriptUnavailable }
            await transform(meeting: meeting, segments: segments)
        } catch {
            try? await persistFailure(error, meetingID: meeting.id, stage: .processing)
        }
    }

    private func transform(meeting: MeetingSnapshot, segments: [TranscriptSegment]) async {
        do {
            try await history.updateMeeting(
                id: meeting.id,
                mutation: .status(.processing, errorMessage: nil)
            )
            let output = try await transformer.transform(
                text: Self.formattedTranscript(segments),
                instructions: Self.processingInstructions(for: meeting)
            )
            try await history.updateMeeting(
                id: meeting.id,
                mutation: .result(
                    processedText: output,
                    resultLanguage: meeting.resultLanguage
                )
            )
            try await history.updateMeeting(
                id: meeting.id,
                mutation: .status(.ready, errorMessage: nil)
            )
        } catch {
            try? await persistFailure(error, meetingID: meeting.id, stage: .processing)
        }
    }

    private func persistFailure(
        _ error: Error,
        meetingID: UUID,
        stage: MeetingRetryStage
    ) async throws {
        let message: String
        if error is URLError || Self.isTransientAPIError(error) {
            message = "Check your network connection, then retry. Captured audio was preserved."
            try await history.updateMeeting(
                id: meetingID,
                mutation: .retryable(message: message, kind: .network, stage: stage)
            )
            return
        }

        if error as? FeatureError == .missingAPIKey {
            message = "Open Whisper Settings to add your OpenAI API key, then retry. Captured audio was preserved."
            try await history.updateMeeting(
                id: meetingID,
                mutation: .retryable(message: message, kind: .missingAPIKey, stage: stage)
            )
            return
        }

        let kind: MeetingFailureKind
        if error is FeatureError {
            kind = .authentication
            message = "Open Whisper Settings to add or replace your OpenAI API key. Captured audio was preserved."
        } else {
            kind = .processing
            message = "Whisper could not process this meeting. Captured audio was preserved."
        }
        try await history.updateMeeting(
            id: meetingID,
            mutation: .failure(message: message, kind: kind, stage: stage)
        )
    }

    private static func isTransientAPIError(_ error: Error) -> Bool {
        guard case .transientAPI = error as? OpenAIClientError else { return false }
        return true
    }

    private static func processingInstructions(for meeting: MeetingSnapshot) -> String {
        guard let language = nonEmpty(meeting.resultLanguage) else {
            return meeting.instructionsSnapshot
        }
        return "\(meeting.instructionsSnapshot)\n\nWrite the result in \(language)."
    }

    private static func formattedTranscript(_ segments: [TranscriptSegment]) -> String {
        segments.map { segment in
            "[\(timestamp(segment.startTime))] \(segment.source == .you ? "You" : "Others"): \(segment.text)"
        }.joined(separator: "\n")
    }

    private static func timestamp(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds / 60) % 60,
            seconds % 60
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
