import Foundation

@MainActor
protocol ActiveModeProviding: Sendable {
    func activeMode() throws -> ModeDefinition
}

extension ModeRepository: ActiveModeProviding {}

@MainActor
protocol DictationHistoryWriting: Sendable {
    @discardableResult
    func createDictation(_ draft: DictationDraft) throws -> UUID
}

extension HistoryRepository: DictationHistoryWriting {}

enum DictationCoordinatorError: Error, Sendable, Equatable {
    case busy
    case notRecording
}

extension DictationCoordinatorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .busy:
            "Another dictation is already running."
        case .notRecording:
            "No dictation is active."
        }
    }
}

actor DictationCoordinator {
    typealias Now = @Sendable () -> Date

    private struct Session: Sendable {
        let id: UUID
        let mode: ModeDefinition
        let target: FocusedTarget
        let startedAt: Date
        var capturedAudio: CapturedAudio?
    }

    private let recorder: any MicrophoneRecorder
    private let openAI: any OpenAIClientProtocol
    private let modeProvider: any ActiveModeProviding
    private let history: any DictationHistoryWriting
    private let insertion: any TextInsertionService
    private let promptBuilder: ModePromptBuilder
    private let now: Now
    private let stateStream: AsyncStream<DictationState>
    private let stateContinuation: AsyncStream<DictationState>.Continuation

    private var state: DictationState = .idle
    private var session: Session?
    private var startAttemptID: UUID?
    private var retainedAudioURL: URL?

    init(
        recorder: any MicrophoneRecorder,
        openAI: any OpenAIClientProtocol,
        modeProvider: any ActiveModeProviding,
        history: any DictationHistoryWriting,
        insertion: any TextInsertionService,
        promptBuilder: ModePromptBuilder = ModePromptBuilder(),
        now: @escaping Now = Date.init
    ) {
        self.recorder = recorder
        self.openAI = openAI
        self.modeProvider = modeProvider
        self.history = history
        self.insertion = insertion
        self.promptBuilder = promptBuilder
        self.now = now
        let stream = AsyncStream<DictationState>.makeStream(bufferingPolicy: .bufferingNewest(20))
        stateStream = stream.stream
        stateContinuation = stream.continuation
        stateContinuation.yield(.idle)
    }

    deinit {
        stateContinuation.finish()
    }

    func states() -> AsyncStream<DictationState> {
        stateStream
    }

    func currentState() -> DictationState {
        state
    }

    func retryAudioURL() -> URL? {
        retainedAudioURL
    }

    func begin(deviceID: String? = nil) async throws {
        guard session == nil, startAttemptID == nil else {
            throw DictationCoordinatorError.busy
        }
        let attemptID = UUID()
        startAttemptID = attemptID
        defer {
            if startAttemptID == attemptID {
                startAttemptID = nil
            }
        }

        deleteRetainedAudio()
        let startedAt = now()

        do {
            let mode = try await modeProvider.activeMode()
            try ensureCurrentStartAttempt(attemptID)
            let target = try await insertion.captureFocusedTarget()
            try ensureCurrentStartAttempt(attemptID)
            try await recorder.start(deviceID: deviceID)
            guard startAttemptID == attemptID else {
                await recorder.cancel()
                throw CancellationError()
            }
            session = Session(
                id: UUID(),
                mode: mode,
                target: target,
                startedAt: startedAt,
                capturedAudio: nil
            )
            emit(.recording(modeName: mode.name))
        } catch {
            guard startAttemptID == attemptID else {
                throw CancellationError()
            }
            emit(.failed(message: error.localizedDescription, textOnClipboard: false))
            throw error
        }
    }

    func finish() async {
        guard case .recording = state, let initialSession = session else {
            return
        }
        let sessionID = initialSession.id
        var capturedAudio: CapturedAudio?
        var insertionResult: InsertionResult?

        do {
            emit(.transcribing)
            let capture = try await recorder.stop()
            capturedAudio = capture
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }
            session?.capturedAudio = capture

            guard capture.containsSpeech else {
                deleteAudio(at: capture.fileURL)
                session = nil
                emit(.idle)
                return
            }

            let transcription = try await openAI.transcribe(
                fileURL: capture.fileURL,
                languageHint: initialSession.mode.languageHint,
                prompt: nil
            )
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            emit(.transforming)
            let transformedText = try await openAI.transform(
                text: transcription.text,
                instructions: promptBuilder.instructions(for: initialSession.mode)
            )
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            emit(.inserting)
            insertionResult = try await insertion.insert(transformedText, into: initialSession.target)
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            let draft = DictationDraft(
                createdAt: initialSession.startedAt,
                duration: capture.duration,
                modeID: initialSession.mode.id,
                modeNameSnapshot: initialSession.mode.name,
                modeInstructionsSnapshot: initialSession.mode.instructions,
                detectedLanguages: transcription.languages?.map(\.language) ?? [],
                originalText: transcription.text,
                outputText: transformedText,
                targetApplicationBundleID: initialSession.target.bundleIdentifier,
                status: .ready
            )
            _ = try await history.createDictation(draft)
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            deleteAudio(at: capture.fileURL)
            session = nil
            retainedAudioURL = nil
            emit(.completed)
        } catch {
            guard isCurrent(sessionID) else {
                if let capturedAudio { deleteAudio(at: capturedAudio.fileURL) }
                return
            }

            let shouldRetainForRetry = state == .transcribing || state == .transforming
            if shouldRetainForRetry, let capturedAudio {
                retainedAudioURL = capturedAudio.fileURL
            } else if let capturedAudio {
                deleteAudio(at: capturedAudio.fileURL)
            }
            session = nil
            emit(
                .failed(
                    message: error.localizedDescription,
                    textOnClipboard: insertionResult == .copiedForManualPaste
                )
            )
        }
    }

    func cancel() async {
        let activeAudioURL = session?.capturedAudio?.fileURL
        let retryURL = retainedAudioURL
        startAttemptID = nil
        session = nil
        retainedAudioURL = nil
        await recorder.cancel()
        if let activeAudioURL { deleteAudio(at: activeAudioURL) }
        if let retryURL { deleteAudio(at: retryURL) }
        emit(.idle)
    }

    private func isCurrent(_ id: UUID) -> Bool {
        session?.id == id
    }

    private func ensureCurrentStartAttempt(_ id: UUID) throws {
        guard startAttemptID == id else {
            throw CancellationError()
        }
    }

    private func emit(_ newState: DictationState) {
        state = newState
        stateContinuation.yield(newState)
    }

    private func deleteRetainedAudio() {
        guard let retainedAudioURL else { return }
        deleteAudio(at: retainedAudioURL)
        self.retainedAudioURL = nil
    }

    private func deleteAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
