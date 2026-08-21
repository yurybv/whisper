@preconcurrency import AVFoundation
import XCTest
@testable import Whisper

@MainActor
final class AVAudioEngineRecorderTests: XCTestCase {
    func testWritesMonoSamplesAndReturnsDeterministicCaptureMetadata() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = FakeAudioCaptureBackend()
        let recorder = AVAudioEngineRecorder(temporaryDirectory: directory, backend: backend)

        try await recorder.start(deviceID: nil)
        backend.emit(Array(repeating: 0.2, count: 4_800))
        let capture = try await recorder.stop()

        XCTAssertEqual(capture.duration, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(capture.peakLevel, 0.2, accuracy: 0.000_01)
        XCTAssertTrue(capture.containsSpeech)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.fileURL.path))
        XCTAssertGreaterThan(try Data(contentsOf: capture.fileURL).count, 44)
        let audioFile = try AVAudioFile(forReading: capture.fileURL)
        XCTAssertEqual(audioFile.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(audioFile.processingFormat.channelCount, 1)
        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.stopCount, 1)
    }

    func testSilentCaptureIsReturnedWithoutSpeech() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = FakeAudioCaptureBackend()
        let recorder = AVAudioEngineRecorder(temporaryDirectory: directory, backend: backend)

        try await recorder.start(deviceID: nil)
        backend.emit(Array(repeating: 0, count: 8_000))
        let capture = try await recorder.stop()

        XCTAssertFalse(capture.containsSpeech)
        XCTAssertEqual(capture.peakLevel, 0)
    }

    func testCancelStopsCaptureAndRemovesTemporaryFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = FakeAudioCaptureBackend()
        let recorder = AVAudioEngineRecorder(temporaryDirectory: directory, backend: backend)

        try await recorder.start(deviceID: "test-device")
        backend.emit(Array(repeating: 0.2, count: 1_600))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)

        await recorder.cancel()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
        XCTAssertEqual(backend.selectedDeviceID, "test-device")
        XCTAssertEqual(backend.stopCount, 1)
    }

    func testDeviceLossFinalizesAndCleansCaptureBeforeThrowing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = FakeAudioCaptureBackend()
        let recorder = AVAudioEngineRecorder(temporaryDirectory: directory, backend: backend)

        try await recorder.start(deviceID: "removed-device")
        backend.emit(Array(repeating: 0.2, count: 1_600))
        backend.disconnectDevice()

        do {
            _ = try await recorder.stop()
            XCTFail("Expected disconnected microphone error")
        } catch {
            XCTAssertEqual(error as? FeatureError, .microphoneDisconnected)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
        XCTAssertEqual(backend.stopCount, 1)
    }

    func testSecondStartIsRejectedWithoutReplacingActiveCapture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = FakeAudioCaptureBackend()
        let recorder = AVAudioEngineRecorder(temporaryDirectory: directory, backend: backend)

        try await recorder.start(deviceID: nil)
        do {
            try await recorder.start(deviceID: nil)
            XCTFail("Expected already recording error")
        } catch {
            XCTAssertEqual(error as? MicrophoneRecorderError, .alreadyRecording)
        }
        await recorder.cancel()
        XCTAssertEqual(backend.startCount, 1)
    }

    func testConcreteBackendRejectsMissingSelectedDevice() {
        let backend = AVAudioEngineCaptureBackend()

        XCTAssertThrowsError(
            try backend.start(
                deviceID: "dev.yury.whisper.missing-device",
                samplesHandler: { _ in },
                deviceLossHandler: {}
            )
        ) { error in
            XCTAssertEqual(error as? MicrophoneRecorderError, .deviceUnavailable)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeAudioCaptureBackend: AudioCaptureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var samplesHandler: (@Sendable ([Float]) -> Void)?
    private var deviceLossHandler: (@Sendable () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var selectedDeviceID: String?

    func start(
        deviceID: String?,
        samplesHandler: @escaping @Sendable ([Float]) -> Void,
        deviceLossHandler: @escaping @Sendable () -> Void
    ) throws {
        lock.withLock {
            startCount += 1
            selectedDeviceID = deviceID
            self.samplesHandler = samplesHandler
            self.deviceLossHandler = deviceLossHandler
        }
    }

    func stop() {
        lock.withLock {
            stopCount += 1
            samplesHandler = nil
            deviceLossHandler = nil
        }
    }

    func emit(_ samples: [Float]) {
        let handler = lock.withLock { samplesHandler }
        handler?(samples)
    }

    func disconnectDevice() {
        let handler = lock.withLock { deviceLossHandler }
        handler?()
    }
}
