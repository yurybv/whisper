@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class AVAudioEngineRecorder: MicrophoneRecorder, @unchecked Sendable {
    static let sampleRate: Double = 16_000
    static let maximumLevelUpdatesPerSecond: TimeInterval = 30

    private final class RecordingSession {
        let fileURL: URL
        var file: AVAudioFile?
        var frameCount: Int64 = 0
        var peakLevel: Float = 0
        var meter = AudioLevelMeter()
        var lastLevelPublication = -TimeInterval.infinity
        var writeFailed = false
        var deviceDisconnected = false
        var backendStopped = false

        init(fileURL: URL, file: AVAudioFile) {
            self.fileURL = fileURL
            self.file = file
        }
    }

    private let temporaryDirectory: URL
    private let backend: any AudioCaptureBackend
    private let silenceDetector: SilenceDetector
    private let now: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var session: RecordingSession?
    private let levelStream: AsyncStream<Float>
    private let levelContinuation: AsyncStream<Float>.Continuation

    convenience init(
        paths: AppPaths,
        silenceDetector: SilenceDetector = SilenceDetector()
    ) {
        self.init(
            temporaryDirectory: paths.temporaryURL,
            backend: AVAudioEngineCaptureBackend(),
            silenceDetector: silenceDetector
        )
    }

    init(
        temporaryDirectory: URL,
        backend: any AudioCaptureBackend = AVAudioEngineCaptureBackend(),
        silenceDetector: SilenceDetector = SilenceDetector(),
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.backend = backend
        self.silenceDetector = silenceDetector
        self.now = now
        let stream = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        levelStream = stream.stream
        levelContinuation = stream.continuation
    }

    func start(deviceID: String?) async throws {
        let recordingSession = try makeSession()
        let accepted = lock.withLock { () -> Bool in
            guard session == nil else {
                return false
            }
            session = recordingSession
            return true
        }
        guard accepted else {
            recordingSession.file = nil
            try? FileManager.default.removeItem(at: recordingSession.fileURL)
            throw MicrophoneRecorderError.alreadyRecording
        }

        do {
            try backend.start(
                deviceID: deviceID,
                samplesHandler: { [weak self] samples in
                    self?.consume(samples)
                },
                deviceLossHandler: { [weak self] in
                    self?.handleDeviceLoss()
                }
            )
        } catch {
            backend.stop()
            lock.withLock {
                if session === recordingSession {
                    session = nil
                }
            }
            recordingSession.file = nil
            try? FileManager.default.removeItem(at: recordingSession.fileURL)
            throw error
        }
    }

    func levels() async -> AsyncStream<Float> {
        levelStream
    }

    func stop() async throws -> CapturedAudio {
        guard let activeSession = lock.withLock({ session }) else {
            throw MicrophoneRecorderError.notRecording
        }

        let shouldStopBackend = lock.withLock { () -> Bool in
            guard !activeSession.backendStopped else {
                return false
            }
            activeSession.backendStopped = true
            return true
        }
        if shouldStopBackend {
            backend.stop()
        }

        let result = lock.withLock { () -> (
            url: URL,
            frameCount: Int64,
            peakLevel: Float,
            writeFailed: Bool,
            deviceDisconnected: Bool
        ) in
            activeSession.file = nil
            if session === activeSession {
                session = nil
            }
            return (
                activeSession.fileURL,
                activeSession.frameCount,
                activeSession.peakLevel,
                activeSession.writeFailed,
                activeSession.deviceDisconnected
            )
        }

        if result.writeFailed || result.deviceDisconnected {
            try? FileManager.default.removeItem(at: result.url)
            if result.deviceDisconnected {
                throw FeatureError.microphoneDisconnected
            }
            throw MicrophoneRecorderError.cannotWriteAudioFile
        }

        let duration = TimeInterval(result.frameCount) / Self.sampleRate
        return CapturedAudio(
            fileURL: result.url,
            duration: duration,
            peakLevel: result.peakLevel,
            containsSpeech: silenceDetector.containsSpeech(
                duration: duration,
                peakLevel: result.peakLevel
            )
        )
    }

    func cancel() async {
        guard let activeSession = lock.withLock({ session }) else {
            return
        }
        let shouldStopBackend = lock.withLock { () -> Bool in
            guard !activeSession.backendStopped else {
                return false
            }
            activeSession.backendStopped = true
            return true
        }
        if shouldStopBackend {
            backend.stop()
        }
        let url = lock.withLock { () -> URL in
            activeSession.file = nil
            if session === activeSession {
                session = nil
            }
            return activeSession.fileURL
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeSession() throws -> RecordingSession {
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let fileURL = temporaryDirectory
                .appendingPathComponent("dictation-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw MicrophoneRecorderError.cannotCreateAudioFile
            }
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            return RecordingSession(fileURL: fileURL, file: file)
        } catch let error as MicrophoneRecorderError {
            throw error
        } catch {
            throw MicrophoneRecorderError.cannotCreateAudioFile
        }
    }

    private func consume(_ samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }
        var publishedLevel: Float?
        lock.withLock {
            guard let session, let file = session.file else {
                return
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ), let channel = buffer.floatChannelData?[0] else {
                session.writeFailed = true
                return
            }

            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                if let baseAddress = source.baseAddress {
                    channel.update(from: baseAddress, count: samples.count)
                }
            }
            do {
                try file.write(from: buffer)
            } catch {
                session.writeFailed = true
                return
            }

            session.frameCount += Int64(samples.count)
            let rawLevel = AudioLevelMeter.normalizedRMS(samples: samples)
            session.peakLevel = max(session.peakLevel, rawLevel)
            let smoothedLevel = session.meter.process(samples: samples)
            let timestamp = now()
            let minimumInterval = 1 / Self.maximumLevelUpdatesPerSecond
            if timestamp - session.lastLevelPublication >= minimumInterval {
                session.lastLevelPublication = timestamp
                publishedLevel = smoothedLevel
            }
        }
        if let publishedLevel {
            levelContinuation.yield(publishedLevel)
        }
    }

    private func handleDeviceLoss() {
        let shouldStopBackend = lock.withLock { () -> Bool in
            guard let session else {
                return false
            }
            session.deviceDisconnected = true
            session.file = nil
            guard !session.backendStopped else {
                return false
            }
            session.backendStopped = true
            return true
        }
        if shouldStopBackend {
            backend.stop()
        }
    }
}

final class AVAudioEngineCaptureBackend: AudioCaptureBackend, @unchecked Sendable {
    private final class ConverterInput: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var wasProvided = false

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }
    }

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var configurationObserver: NSObjectProtocol?
    private var selectedDeviceID: String?
    private var samplesHandler: (@Sendable ([Float]) -> Void)?
    private var deviceLossHandler: (@Sendable () -> Void)?

    func start(
        deviceID: String?,
        samplesHandler: @escaping @Sendable ([Float]) -> Void,
        deviceLossHandler: @escaping @Sendable () -> Void
    ) throws {
        let audioEngine = AVAudioEngine()
        if let deviceID {
            try selectInputDevice(uid: deviceID, for: audioEngine)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: AVAudioEngineRecorder.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw MicrophoneRecorderError.deviceUnavailable
        }

        lock.withLock {
            engine = audioEngine
            converter = audioConverter
            selectedDeviceID = deviceID
            self.samplesHandler = samplesHandler
            self.deviceLossHandler = deviceLossHandler
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer, to: outputFormat)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        let resources = lock.withLock { () -> (AVAudioEngine?, NSObjectProtocol?) in
            let resources = (engine, configurationObserver)
            engine = nil
            converter = nil
            configurationObserver = nil
            selectedDeviceID = nil
            samplesHandler = nil
            deviceLossHandler = nil
            return resources
        }
        if let observer = resources.1 {
            NotificationCenter.default.removeObserver(observer)
        }
        if let audioEngine = resources.0 {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) {
        let resources = lock.withLock { (converter, samplesHandler) }
        guard let converter = resources.0, let handler = resources.1 else {
            return
        }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            return
        }

        let converterInput = ConverterInput(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outputStatus in
            guard !converterInput.wasProvided else {
                outputStatus.pointee = .noDataNow
                return nil
            }
            converterInput.wasProvided = true
            outputStatus.pointee = .haveData
            return converterInput.buffer
        }
        guard status != .error,
              conversionError == nil,
              let channel = convertedBuffer.floatChannelData?[0] else {
            return
        }
        let samples = Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(convertedBuffer.frameLength)
            )
        )
        handler(samples)
    }

    private func handleConfigurationChange() {
        let resources = lock.withLock { (engine, selectedDeviceID, deviceLossHandler) }
        guard let audioEngine = resources.0, let handler = resources.2 else {
            return
        }
        let selectedDeviceMissing = resources.1.map { !Self.inputDeviceExists(uid: $0) } ?? false
        let inputUnavailable = audioEngine.inputNode.inputFormat(forBus: 0).channelCount == 0
        if selectedDeviceMissing || inputUnavailable {
            handler()
        }
    }

    private func selectInputDevice(uid: String, for audioEngine: AVAudioEngine) throws {
        guard let deviceID = Self.audioDeviceID(uid: uid),
              let audioUnit = audioEngine.inputNode.audioUnit else {
            throw MicrophoneRecorderError.deviceUnavailable
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneRecorderError.deviceUnavailable
        }
    }

    private static func inputDeviceExists(uid: String) -> Bool {
        audioDeviceID(uid: uid) != nil
    }

    private static func audioDeviceID(uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        let devicesStatus = deviceIDs.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        guard devicesStatus == noErr else {
            return nil
        }

        for deviceID in deviceIDs where hasInputChannels(deviceID) {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var unmanagedDeviceUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(
                deviceID,
                &uidAddress,
                0,
                nil,
                &uidSize,
                &unmanagedDeviceUID
            )
            if status == noErr,
               let deviceUID = unmanagedDeviceUID?.takeUnretainedValue(),
               deviceUID as String == uid {
                return deviceID
            }
        }
        return nil
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr,
        dataSize >= MemoryLayout<AudioBufferList>.size else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            buffer
        ) == noErr else {
            return false
        }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return audioBuffers.contains { $0.mNumberChannels > 0 }
    }
}
