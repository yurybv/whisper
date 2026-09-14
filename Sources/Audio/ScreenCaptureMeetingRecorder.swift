@preconcurrency import AVFoundation
import AudioToolbox
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureMeetingRecorder: MeetingRecorder, @unchecked Sendable {
    static let maximumSupportedDuration: TimeInterval = 10_800
    static let maximumLevelUpdatesPerSecond: TimeInterval = 30

    private enum TerminalIntent: Equatable {
        case stop
        case cancel
        case interrupt
    }

    private enum TerminalResult {
        case captured(CapturedMeeting)
        case cancelled
    }

    private final class RecordingSession: @unchecked Sendable {
        let directoryURL: URL
        let microphoneWriter: any MeetingTrackWriter
        let systemAudioWriter: any MeetingTrackWriter
        let startedAt: Date
        let startedUptime: TimeInterval
        var microphoneLevel: Float = 0
        var systemAudioLevel: Float = 0
        var lastLevelPublication = -TimeInterval.infinity
        var microphoneFirstPresentationTime: TimeInterval?
        var systemAudioFirstPresentationTime: TimeInterval?
        var deadline: (any MeetingDeadline)?
        var interruption: MeetingCaptureInterruptionReason?
        var startTask: Task<Void, Error>!
        var terminalIntent: TerminalIntent?
        var terminalTask: Task<TerminalResult, Error>?
        var acceptsInterruptions = true

        init(
            directoryURL: URL,
            microphoneWriter: any MeetingTrackWriter,
            systemAudioWriter: any MeetingTrackWriter,
            startedAt: Date,
            startedUptime: TimeInterval
        ) {
            self.directoryURL = directoryURL
            self.microphoneWriter = microphoneWriter
            self.systemAudioWriter = systemAudioWriter
            self.startedAt = startedAt
            self.startedUptime = startedUptime
        }
    }

    private let paths: AppPaths
    private let backend: any MeetingCaptureBackend
    private let diskSpaceMonitor: DiskSpaceMonitor
    private let writerFactory: @Sendable (URL) throws -> any MeetingTrackWriter
    private let deadlineScheduler: any MeetingDeadlineScheduling
    private let now: @Sendable () -> Date
    private let uptime: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var session: RecordingSession?
    private let levelStream: AsyncStream<MeetingAudioLevels>
    private let levelContinuation: AsyncStream<MeetingAudioLevels>.Continuation
    private let completionStream: AsyncStream<MeetingCaptureCompletion>
    private let completionContinuation: AsyncStream<MeetingCaptureCompletion>.Continuation

    convenience init(paths: AppPaths) {
        self.init(
            paths: paths,
            backend: ScreenCaptureKitMeetingBackend(),
            diskSpaceMonitor: DiskSpaceMonitor(),
            writerFactory: { SampleBufferAudioWriter(outputURL: $0) },
            deadlineScheduler: TaskMeetingDeadlineScheduler()
        )
    }

    init(
        paths: AppPaths,
        backend: any MeetingCaptureBackend,
        diskSpaceMonitor: DiskSpaceMonitor,
        writerFactory: @escaping @Sendable (URL) throws -> any MeetingTrackWriter,
        deadlineScheduler: any MeetingDeadlineScheduling,
        now: @escaping @Sendable () -> Date = { Date() },
        uptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.paths = paths
        self.backend = backend
        self.diskSpaceMonitor = diskSpaceMonitor
        self.writerFactory = writerFactory
        self.deadlineScheduler = deadlineScheduler
        self.now = now
        self.uptime = uptime
        let levels = AsyncStream<MeetingAudioLevels>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        levelStream = levels.stream
        levelContinuation = levels.continuation
        let completions = AsyncStream<MeetingCaptureCompletion>.makeStream()
        completionStream = completions.stream
        completionContinuation = completions.continuation
    }

    func start(configuration: MeetingCaptureConfiguration) async throws {
        guard configuration.maximumDuration > 0 else {
            throw MeetingRecorderError.invalidMaximumDuration
        }

        let activeSession = try lock.withLock { () throws -> RecordingSession in
            guard session == nil else {
                throw MeetingRecorderError.alreadyRecording
            }
            let diskState = try diskSpaceMonitor.state(for: paths.recordingsURL)
            if case let .blocked(availableBytes) = diskState {
                throw MeetingRecorderError.insufficientDiskSpace(availableBytes: availableBytes)
            }

            let directory: URL
            do {
                directory = try paths.recordingDirectory(
                    for: configuration.meetingID,
                    create: false
                )
                guard !FileManager.default.fileExists(atPath: directory.path) else {
                    throw MeetingRecorderError.recordingAlreadyExists
                }
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false
                )
            } catch let error as MeetingRecorderError {
                throw error
            } catch {
                throw MeetingRecorderError.cannotCreateRecordingDirectory
            }

            let microphoneWriter: any MeetingTrackWriter
            let systemAudioWriter: any MeetingTrackWriter
            do {
                microphoneWriter = try writerFactory(
                    directory.appendingPathComponent("microphone.m4a")
                )
                do {
                    systemAudioWriter = try writerFactory(
                        directory.appendingPathComponent("system.m4a")
                    )
                } catch {
                    microphoneWriter.cancel()
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw MeetingRecorderError.cannotCreateRecordingDirectory
            }

            let activeSession = RecordingSession(
                directoryURL: directory,
                microphoneWriter: microphoneWriter,
                systemAudioWriter: systemAudioWriter,
                startedAt: now(),
                startedUptime: uptime()
            )
            activeSession.startTask = Task { [weak self, weak activeSession, backend] in
                guard let self, let activeSession else { throw CancellationError() }
                try await backend.start(
                    microphoneDeviceID: configuration.microphoneDeviceID,
                    sampleHandler: { [weak self, weak activeSession] source, sampleBuffer in
                        guard let self, let activeSession else { return }
                        self.consume(sampleBuffer, from: source, session: activeSession)
                    },
                    interruptionHandler: { [weak self, weak activeSession] source in
                        guard let self, let activeSession else { return }
                        Task {
                            await self.interrupt(
                                reason: source.interruptionReason,
                                session: activeSession
                            )
                        }
                    }
                )
            }
            session = activeSession
            return activeSession
        }

        do {
            try await activeSession.startTask.value
        } catch {
            let task = terminalTask(for: activeSession, requested: .cancel)
            _ = try? await task.value
            throw error
        }

        if let terminalTask = lock.withLock({ activeSession.terminalTask }) {
            _ = try? await terminalTask.value
            throw CancellationError()
        }

        let duration = min(configuration.maximumDuration, Self.maximumSupportedDuration)
        let deadline = deadlineScheduler.schedule(after: duration) { [weak self] in
            guard let self else { return }
            Task { await self.finalizeAtMaximumDuration() }
        }
        let shouldKeepDeadline = lock.withLock { () -> Bool in
            guard session === activeSession, activeSession.terminalTask == nil else {
                return false
            }
            activeSession.deadline = deadline
            return true
        }
        if !shouldKeepDeadline {
            deadline.cancel()
        }
        levelContinuation.yield(
            MeetingAudioLevels(microphone: 0, systemAudio: 0, elapsedTime: 0)
        )
    }

    func levels() async -> AsyncStream<MeetingAudioLevels> {
        levelStream
    }

    func completions() async -> AsyncStream<MeetingCaptureCompletion> {
        completionStream
    }

    func stop() async throws -> CapturedMeeting {
        guard let activeSession = lock.withLock({ session }) else {
            throw MeetingRecorderError.notRecording
        }
        switch try await terminalTask(for: activeSession, requested: .stop).value {
        case let .captured(capture):
            return capture
        case .cancelled:
            throw CancellationError()
        }
    }

    func interrupt(reason: MeetingCaptureInterruptionReason) async {
        guard let activeSession = lock.withLock({ session }) else { return }
        await interrupt(reason: reason, session: activeSession)
    }

    func cancel() async {
        guard let activeSession = lock.withLock({ session }) else { return }
        _ = try? await terminalTask(for: activeSession, requested: .cancel).value
    }

    private func consume(
        _ sampleBuffer: CMSampleBuffer,
        from source: MeetingAudioSource,
        session activeSession: RecordingSession
    ) {
        var appendFailed = false
        var publication: MeetingAudioLevels?
        lock.withLock {
            guard session === activeSession, activeSession.terminalTask == nil else { return }
            let writer = source == .microphone
                ? activeSession.microphoneWriter
                : activeSession.systemAudioWriter
            do {
                try writer.append(sampleBuffer)
            } catch {
                appendFailed = true
                return
            }

            let presentationTime = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            )
            if presentationTime.isFinite {
                switch source {
                case .microphone where activeSession.microphoneFirstPresentationTime == nil:
                    activeSession.microphoneFirstPresentationTime = presentationTime
                case .systemAudio where activeSession.systemAudioFirstPresentationTime == nil:
                    activeSession.systemAudioFirstPresentationTime = presentationTime
                default:
                    break
                }
            }

            let level = SampleBufferAudioLevel.normalizedRMS(sampleBuffer)
            switch source {
            case .microphone:
                activeSession.microphoneLevel = level
            case .systemAudio:
                activeSession.systemAudioLevel = level
            }
            let elapsed = max(0, uptime() - activeSession.startedUptime)
            let minimumInterval = 1 / Self.maximumLevelUpdatesPerSecond
            if elapsed - activeSession.lastLevelPublication >= minimumInterval {
                activeSession.lastLevelPublication = elapsed
                publication = MeetingAudioLevels(
                    microphone: activeSession.microphoneLevel,
                    systemAudio: activeSession.systemAudioLevel,
                    elapsedTime: elapsed
                )
            }
        }
        if appendFailed {
            Task {
                await interrupt(reason: source.interruptionReason, session: activeSession)
            }
        } else if let publication {
            levelContinuation.yield(publication)
        }
    }

    private func finalizeAtMaximumDuration() async {
        guard let activeSession = lock.withLock({ session }) else { return }
        _ = try? await terminalTask(for: activeSession, requested: .stop).value
    }

    private func interrupt(
        reason: MeetingCaptureInterruptionReason,
        session activeSession: RecordingSession
    ) async {
        guard lock.withLock({ session === activeSession }) else { return }
        _ = try? await terminalTask(
            for: activeSession,
            requested: .interrupt,
            interruption: reason
        ).value
    }

    private func terminalTask(
        for activeSession: RecordingSession,
        requested: TerminalIntent,
        interruption: MeetingCaptureInterruptionReason? = nil
    ) -> Task<TerminalResult, Error> {
        lock.withLock {
            if let interruption,
               activeSession.acceptsInterruptions,
               activeSession.terminalIntent == nil || activeSession.terminalIntent == .interrupt {
                activeSession.interruption = Self.combine(
                    activeSession.interruption,
                    interruption
                )
            }
            if let existing = activeSession.terminalTask {
                return existing
            }

            activeSession.terminalIntent = requested
            activeSession.deadline?.cancel()
            let startTask = activeSession.startTask!
            let task: Task<TerminalResult, Error> = Task { [self, backend, now] in
                do {
                    try await startTask.value
                } catch {
                    await backend.stop()
                    activeSession.microphoneWriter.cancel()
                    activeSession.systemAudioWriter.cancel()
                    try? FileManager.default.removeItem(at: activeSession.directoryURL)
                    clearSession(activeSession)
                    throw error
                }

                await backend.stop()
                if requested == .cancel {
                    activeSession.microphoneWriter.cancel()
                    activeSession.systemAudioWriter.cancel()
                    try? FileManager.default.removeItem(at: activeSession.directoryURL)
                    clearSession(activeSession)
                    return .cancelled
                }

                async let microphoneURL = Self.finish(activeSession.microphoneWriter)
                async let systemAudioURL = Self.finish(activeSession.systemAudioWriter)
                let tracks = await (microphoneURL, systemAudioURL)
                let endedAt = now()
                let timing = lock.withLock {
                    Self.trackOffsets(
                        microphone: activeSession.microphoneFirstPresentationTime,
                        systemAudio: activeSession.systemAudioFirstPresentationTime
                    )
                }
                var failureReason = lock.withLock {
                    activeSession.acceptsInterruptions = false
                    return activeSession.interruption
                }
                failureReason = Self.combine(failureReason, Self.missingReason(for: tracks))
                if let failureReason {
                    let failure = MeetingCaptureFailure(
                        unavailableSource: failureReason,
                        microphoneURL: tracks.0,
                        systemAudioURL: tracks.1,
                        microphoneStartOffset: timing.microphone,
                        systemAudioStartOffset: timing.systemAudio,
                        startedAt: activeSession.startedAt,
                        endedAt: endedAt
                    )
                    clearSession(activeSession)
                    completionContinuation.yield(.failed(failure))
                    throw failure
                }

                let capture = CapturedMeeting(
                    microphoneURL: tracks.0!,
                    systemAudioURL: tracks.1!,
                    microphoneStartOffset: timing.microphone,
                    systemAudioStartOffset: timing.systemAudio,
                    startedAt: activeSession.startedAt,
                    endedAt: endedAt
                )
                clearSession(activeSession)
                completionContinuation.yield(.completed(capture))
                return .captured(capture)
            }
            activeSession.terminalTask = task
            return task
        }
    }

    private static func missingReason(
        for tracks: (URL?, URL?)
    ) -> MeetingCaptureInterruptionReason? {
        switch tracks {
        case (nil, nil): .bothSources
        case (nil, _): .microphone
        case (_, nil): .systemAudio
        case (_?, _?): nil
        }
    }

    private static func combine(
        _ lhs: MeetingCaptureInterruptionReason?,
        _ rhs: MeetingCaptureInterruptionReason?
    ) -> MeetingCaptureInterruptionReason? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs == rhs ? lhs : .bothSources
    }

    private static func trackOffsets(
        microphone: TimeInterval?,
        systemAudio: TimeInterval?
    ) -> (microphone: TimeInterval, systemAudio: TimeInterval) {
        guard let microphone, let systemAudio else { return (0, 0) }
        let origin = min(microphone, systemAudio)
        return (
            microphone: max(0, microphone - origin),
            systemAudio: max(0, systemAudio - origin)
        )
    }

    private func clearSession(_ activeSession: RecordingSession) {
        lock.withLock {
            if session === activeSession {
                session = nil
            }
        }
    }

    private static func finish(_ writer: any MeetingTrackWriter) async -> URL? {
        try? await writer.finish()
    }
}

private extension MeetingAudioSource {
    var interruptionReason: MeetingCaptureInterruptionReason {
        switch self {
        case .microphone: .microphone
        case .systemAudio: .systemAudio
        }
    }
}

private enum SampleBufferAudioLevel {
    static func normalizedRMS(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            return 0
        }
        var requiredSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: nil
        ) == noErr, requiredSize >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }
        let audioBufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        var retainedBlockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        ) == noErr else {
            return 0
        }

        var squaredSum: Double = 0
        var sampleCount = 0
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<count {
                let sample = Double(samples[index])
                squaredSum += sample * sample
            }
            sampleCount += count
        }
        guard sampleCount > 0 else { return 0 }
        return min(1, Float(sqrt(squaredSum / Double(sampleCount))))
    }
}

final class TaskMeetingDeadlineScheduler: MeetingDeadlineScheduling, @unchecked Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> any MeetingDeadline {
        TaskMeetingDeadline(interval: interval, action: action)
    }
}

private final class TaskMeetingDeadline: MeetingDeadline, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        task = Task {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }
}

final class ScreenCaptureKitMeetingBackend: NSObject, MeetingCaptureBackend, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let systemAudioQueue = DispatchQueue(label: "dev.yury.whisper.system-audio-capture")
    private let microphoneQueue = DispatchQueue(label: "dev.yury.whisper.microphone-capture")
    private var stream: SCStream?
    private var isStopping = false
    private var microphoneObserver: NSObjectProtocol?
    private var selectedMicrophoneDeviceID: String?
    private var sampleHandler: (@Sendable (MeetingAudioSource, CMSampleBuffer) -> Void)?
    private var interruptionHandler: (@Sendable (MeetingAudioSource) -> Void)?

    func start(
        microphoneDeviceID: String?,
        sampleHandler: @escaping @Sendable (MeetingAudioSource, CMSampleBuffer) -> Void,
        interruptionHandler: @escaping @Sendable (MeetingAudioSource) -> Void
    ) async throws {
        guard lock.withLock({ stream == nil }) else {
            throw MeetingRecorderError.alreadyRecording
        }
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw MeetingRecorderError.captureUnavailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 44_100
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = microphoneDeviceID

        let captureStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try captureStream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: systemAudioQueue
        )
        try captureStream.addStreamOutput(
            self,
            type: .microphone,
            sampleHandlerQueue: microphoneQueue
        )
        lock.withLock {
            stream = captureStream
            isStopping = false
            selectedMicrophoneDeviceID = microphoneDeviceID
                ?? AVCaptureDevice.default(for: .audio)?.uniqueID
            self.sampleHandler = sampleHandler
            self.interruptionHandler = interruptionHandler
        }
        installMicrophoneObserver()
        do {
            try await captureStream.startCapture()
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        let resources = lock.withLock { () -> (SCStream?, NSObjectProtocol?) in
            isStopping = true
            let resources = (stream, microphoneObserver)
            microphoneObserver = nil
            return resources
        }
        if let observer = resources.1 {
            NotificationCenter.default.removeObserver(observer)
        }
        if let stream = resources.0 {
            try? await stream.stopCapture()
        }
        lock.withLock {
            stream = nil
            selectedMicrophoneDeviceID = nil
            sampleHandler = nil
            interruptionHandler = nil
            isStopping = false
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        let source: MeetingAudioSource
        switch outputType {
        case .audio: source = .systemAudio
        case .microphone: source = .microphone
        default: return
        }
        let handler = lock.withLock { sampleHandler }
        handler?(source, sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let handler = lock.withLock { isStopping ? nil : interruptionHandler }
        handler?(.systemAudio)
    }

    private func installMicrophoneObserver() {
        microphoneObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self, let device = notification.object as? AVCaptureDevice else { return }
            let resources = self.lock.withLock {
                (self.selectedMicrophoneDeviceID, self.interruptionHandler)
            }
            if resources.0 == device.uniqueID {
                resources.1?(.microphone)
            }
        }
    }
}
