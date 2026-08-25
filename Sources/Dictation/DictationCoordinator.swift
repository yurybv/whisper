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
    case noRetryAvailable
}

extension DictationCoordinatorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .busy:
            "Another dictation is already running."
        case .notRecording:
            "No dictation is active."
        case .noRetryAvailable:
            "No failed dictation is available to retry."
        }
    }
}

actor DictationCoordinator {
    typealias Now = @Sendable () -> Date

    private struct Session: Sendable {
        let id: UUID
        let historyID: UUID
        let mode: ModeDefinition
        let target: FocusedTarget
        let startedAt: Date
        var capturedAudio: CapturedAudio?
        var transcription: TranscriptionResponse?
        var transformedText: String?
        var insertionResult: InsertionResult?
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
        session?.capturedAudio?.fileURL
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
                historyID: UUID(),
                mode: mode,
                target: target,
                startedAt: startedAt,
                capturedAudio: nil,
                transcription: nil,
                transformedText: nil,
                insertionResult: nil
            )
            emit(.recording(modeName: mode.name))
        } catch {
            guard startAttemptID == attemptID else {
                throw CancellationError()
            }
            emit(
                .failed(
                    message: DictationErrorPresentation.message(for: error, recovery: .none),
                    textOnClipboard: false,
                    recovery: .none
                )
            )
            throw error
        }
    }

    func finish() async {
        guard case .recording = state, let initialSession = session else {
            return
        }
        let sessionID = initialSession.id
        do {
            let capture = try await recorder.stop()
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
        } catch let failure as MicrophoneCaptureFailure {
            guard isCurrent(sessionID) else {
                deleteAudio(at: failure.capturedAudio.fileURL)
                return
            }
            session?.capturedAudio = failure.capturedAudio
            let recovery: DictationRecovery = failure.capturedAudio.containsSpeech
                ? .retryOrDiscard
                : .discardOnly
            emit(
                .failed(
                    message: DictationErrorPresentation.message(
                        for: failure,
                        recovery: recovery
                    ),
                    textOnClipboard: false,
                    recovery: recovery
                )
            )
            return
        } catch {
            guard isCurrent(sessionID) else {
                return
            }
            session = nil
            emit(
                .failed(
                    message: DictationErrorPresentation.message(for: error, recovery: .none),
                    textOnClipboard: false,
                    recovery: .none
                )
            )
            return
        }

        guard let capturedSession = session, capturedSession.id == sessionID else { return }
        await process(sessionID: capturedSession.id)
    }

    func retry() async throws {
        guard case let .failed(_, _, recovery) = state,
              recovery.canRetry,
              let retrySession = session,
              retrySession.capturedAudio != nil else {
            throw DictationCoordinatorError.noRetryAvailable
        }
        await process(sessionID: retrySession.id)
    }

    func discardFailed() {
        guard case let .failed(_, _, recovery) = state, recovery.canDiscard else { return }
        if let audioURL = session?.capturedAudio?.fileURL {
            deleteAudio(at: audioURL)
        }
        session = nil
        emit(.idle)
    }

    @discardableResult
    func cancel() async -> Bool {
        guard case .inserting = state else {
            let activeAudioURL = session?.capturedAudio?.fileURL
            startAttemptID = nil
            session = nil
            await recorder.cancel()
            if let activeAudioURL { deleteAudio(at: activeAudioURL) }
            emit(.idle)
            return true
        }
        return false
    }

    private func process(sessionID: UUID) async {
        guard let capture = session?.capturedAudio, isCurrent(sessionID) else { return }

        do {
            let transcription: TranscriptionResponse
            if let storedTranscription = session?.transcription {
                transcription = storedTranscription
            } else {
                guard let mode = session?.mode else { return }
                emit(.transcribing)
                let response = try await openAI.transcribe(
                    fileURL: capture.fileURL,
                    languageHint: mode.languageHint,
                    prompt: nil
                )
                guard isCurrent(sessionID) else {
                    deleteAudio(at: capture.fileURL)
                    return
                }
                session?.transcription = response
                transcription = response
            }

            let transformedText: String
            if let storedText = session?.transformedText {
                transformedText = storedText
            } else {
                guard let mode = session?.mode else { return }
                emit(.transforming)
                let response = try await openAI.transform(
                    text: transcription.text,
                    instructions: promptBuilder.instructions(for: mode)
                )
                guard isCurrent(sessionID) else {
                    deleteAudio(at: capture.fileURL)
                    return
                }
                session?.transformedText = response
                transformedText = response
            }

            let insertionResult: InsertionResult
            if let storedResult = session?.insertionResult {
                emit(.inserting)
                insertionResult = storedResult
            } else {
                guard let target = session?.target else { return }
                emit(.inserting)
                let result = try await insertion.insert(transformedText, into: target)
                guard isCurrent(sessionID) else {
                    deleteAudio(at: capture.fileURL)
                    return
                }
                session?.insertionResult = result
                insertionResult = result
            }

            guard let currentSession = session, currentSession.id == sessionID else { return }
            let draft = DictationDraft(
                id: currentSession.historyID,
                createdAt: currentSession.startedAt,
                duration: capture.duration,
                modeID: currentSession.mode.id,
                modeNameSnapshot: currentSession.mode.name,
                modeInstructionsSnapshot: currentSession.mode.instructions,
                detectedLanguages: transcription.languages?.map(\.language) ?? [],
                originalText: transcription.text,
                outputText: transformedText,
                targetApplicationBundleID: currentSession.target.bundleIdentifier,
                status: .ready
            )
            _ = try await history.createDictation(draft)
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            deleteAudio(at: capture.fileURL)
            session = nil
            emit(.completed(insertionResult))
        } catch {
            guard isCurrent(sessionID) else {
                deleteAudio(at: capture.fileURL)
                return
            }

            let recovery = recoveryDisposition(for: error)
            emit(
                .failed(
                    message: DictationErrorPresentation.message(
                        for: error,
                        recovery: recovery
                    ),
                    textOnClipboard: session?.insertionResult == .copiedForManualPaste,
                    recovery: recovery
                )
            )
        }
    }

    private func recoveryDisposition(for error: Error) -> DictationRecovery {
        switch error {
        case OpenAIClientError.uploadTooLarge, OpenAIClientError.unreadableAudioFile:
            .discardOnly
        default:
            .retryOrDiscard
        }
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

    private func deleteAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
