@preconcurrency import CoreMedia
import Foundation
import XCTest
@testable import Whisper

@MainActor
final class ScreenCaptureMeetingRecorderTests: XCTestCase {
    func testReturnsSeparateDurableTracksAfterBothWritersFinalize() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let meetingID = UUID()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(
                meetingID: meetingID,
                microphoneDeviceID: "selected-mic",
                maximumDuration: 90
            )
        )
        let capture = try await fixture.recorder.stop()

        XCTAssertEqual(capture.microphoneURL.lastPathComponent, "microphone.m4a")
        XCTAssertEqual(capture.systemAudioURL.lastPathComponent, "system.m4a")
        XCTAssertEqual(capture.microphoneURL.deletingLastPathComponent(), capture.systemAudioURL.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.microphoneURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.systemAudioURL.path))
        XCTAssertEqual(fixture.backend.microphoneDeviceID, "selected-mic")
        XCTAssertEqual(fixture.backend.startCount, 1)
        XCTAssertEqual(fixture.backend.stopCount, 1)
        XCTAssertEqual(fixture.writers.finishCount, 2)
    }

    func testRejectsSecondStartWithoutReplacingActiveCapture() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let firstID = UUID()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: firstID, maximumDuration: 60)
        )
        do {
            try await fixture.recorder.start(
                configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
            )
            XCTFail("Expected already recording error")
        } catch {
            XCTAssertEqual(error as? MeetingRecorderError, .alreadyRecording)
        }

        await fixture.recorder.cancel()
        XCTAssertEqual(fixture.backend.startCount, 1)
    }

    func testMicrophoneLossFinalizesAndPreservesBothAvailableTracks() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        var completions = (await fixture.recorder.completions()).makeAsyncIterator()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )
        await fixture.recorder.interrupt(reason: .microphone)

        let nextCompletion = await completions.next()
        let completion = try XCTUnwrap(nextCompletion)
        guard case let .failed(failure) = completion else {
            return XCTFail("Expected partial capture completion")
        }
        XCTAssertEqual(failure.unavailableSource, .microphone)
        XCTAssertNotNil(failure.microphoneURL)
        XCTAssertNotNil(failure.systemAudioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(failure.microphoneURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(failure.systemAudioURL).path))
        XCTAssertEqual(fixture.backend.stopCount, 1)
        XCTAssertEqual(fixture.writers.finishCount, 2)
    }

    func testScreenCaptureLossPreservesMicrophoneTrackWhenSystemTrackCannotFinalize() async throws {
        let fixture = try makeFixture(failingTrackName: "system.m4a")
        defer { fixture.removeFiles() }
        var completions = (await fixture.recorder.completions()).makeAsyncIterator()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )
        await fixture.recorder.interrupt(reason: .systemAudio)

        let nextCompletion = await completions.next()
        let completion = try XCTUnwrap(nextCompletion)
        guard case let .failed(failure) = completion else {
            return XCTFail("Expected partial capture completion")
        }
        XCTAssertEqual(failure.unavailableSource, .systemAudio)
        XCTAssertNotNil(failure.microphoneURL)
        XCTAssertNil(failure.systemAudioURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(failure.microphoneURL).path))
    }

    func testCancelStopsCaptureAndDeletesOnlyCurrentMeetingDirectory() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let meetingID = UUID()
        let unrelatedID = UUID()
        let unrelatedDirectory = try fixture.paths.recordingDirectory(for: unrelatedID)
        let meetingDirectory = try fixture.paths.recordingDirectory(for: meetingID, create: false)

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: meetingID, maximumDuration: 60)
        )
        await fixture.recorder.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: meetingDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedDirectory.path))
        XCTAssertEqual(fixture.writers.cancelCount, 2)
    }

    func testBlocksStartBelowDiskThresholdBeforeStartingCapture() async throws {
        let fixture = try makeFixture(availableBytes: 1_999_999_999)
        defer { fixture.removeFiles() }

        do {
            try await fixture.recorder.start(
                configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
            )
            XCTFail("Expected insufficient disk error")
        } catch {
            XCTAssertEqual(
                error as? MeetingRecorderError,
                .insufficientDiskSpace(availableBytes: 1_999_999_999)
            )
        }
        XCTAssertEqual(fixture.backend.startCount, 0)
        XCTAssertEqual(fixture.writers.createdURLs.count, 0)
    }

    func testCapsConfiguredDeadlineAtThreeHours() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(
                meetingID: UUID(),
                maximumDuration: 99_999
            )
        )

        XCTAssertEqual(fixture.scheduler.scheduledInterval, 10_800)
        await fixture.recorder.cancel()
    }

    func testDeadlineFinalizesPublishesCompletionAndReleasesRecorder() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        var completions = (await fixture.recorder.completions()).makeAsyncIterator()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )
        fixture.scheduler.fire()

        let nextCompletion = await completions.next()
        let completion = try XCTUnwrap(nextCompletion)
        guard case let .completed(capture) = completion else {
            return XCTFail("Expected successful deadline completion")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.microphoneURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.systemAudioURL.path))

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )
        await fixture.recorder.cancel()
    }

    func testRoutesSamplesPublishesLevelsAndPreservesTrackOffsets() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        var levels = (await fixture.recorder.levels()).makeAsyncIterator()

        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )
        _ = await levels.next()
        fixture.clock.value = 1
        fixture.backend.emit(
            try makeTestAudioSampleBuffer(presentationSeconds: 10, amplitude: 0.25),
            from: .systemAudio
        )
        let nextSystemLevel = await levels.next()
        let systemLevel = try XCTUnwrap(nextSystemLevel)
        fixture.clock.value = 1.1
        fixture.backend.emit(
            try makeTestAudioSampleBuffer(presentationSeconds: 10.5, amplitude: 0.5),
            from: .microphone
        )
        let nextMicrophoneLevel = await levels.next()
        let microphoneLevel = try XCTUnwrap(nextMicrophoneLevel)

        let capture = try await fixture.recorder.stop()
        XCTAssertEqual(fixture.writers.appendCount(for: "system.m4a"), 1)
        XCTAssertEqual(fixture.writers.appendCount(for: "microphone.m4a"), 1)
        XCTAssertEqual(systemLevel.systemAudio, 0.25, accuracy: 0.001)
        XCTAssertEqual(microphoneLevel.microphone, 0.5, accuracy: 0.001)
        XCTAssertEqual(capture.systemAudioStartOffset, 0, accuracy: 0.001)
        XCTAssertEqual(capture.microphoneStartOffset, 0.5, accuracy: 0.001)
    }

    func testExistingMeetingDirectoryIsNeverOverwrittenOrDeleted() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let meetingID = UUID()
        let directory = try fixture.paths.recordingDirectory(for: meetingID)
        let sentinel = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        do {
            try await fixture.recorder.start(
                configuration: MeetingCaptureConfiguration(meetingID: meetingID)
            )
            XCTFail("Expected existing recording error")
        } catch {
            XCTAssertEqual(error as? MeetingRecorderError, .recordingAlreadyExists)
        }
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
        XCTAssertEqual(fixture.backend.startCount, 0)
    }

    func testOverlappingSourceLossIsReportedAsBothSources() async throws {
        let fixture = try makeFixture(suspendFinish: true)
        defer { fixture.removeFiles() }
        var completions = (await fixture.recorder.completions()).makeAsyncIterator()
        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )

        let microphoneLoss = Task {
            await fixture.recorder.interrupt(reason: .microphone)
        }
        await fixture.writers.waitUntilFinishSuspended()
        let systemLoss = Task {
            await fixture.recorder.interrupt(reason: .systemAudio)
        }
        await Task.yield()
        await fixture.writers.resumeFinish()
        await microphoneLoss.value
        await systemLoss.value

        let nextCompletion = await completions.next()
        let completion = try XCTUnwrap(nextCompletion)
        guard case let .failed(failure) = completion else {
            return XCTFail("Expected partial capture completion")
        }
        XCTAssertEqual(failure.unavailableSource, .bothSources)
    }

    func testStopDuringSuspendedStartCannotLeaveBackendCapturing() async throws {
        let fixture = try makeFixture(suspendStart: true)
        defer { fixture.removeFiles() }
        let configuration = MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        let startTask = Task { try await fixture.recorder.start(configuration: configuration) }
        await fixture.backend.waitUntilStartSuspended()

        let stopTask = Task { try await fixture.recorder.stop() }
        try await Task.sleep(for: .milliseconds(10))
        await fixture.backend.resumeStart()
        await fixture.backend.waitUntilStopCalled()

        _ = try await stopTask.value
        do {
            try await startTask.value
            XCTFail("Expected overtaken start to be cancelled")
        } catch is CancellationError {
        }
        XCTAssertFalse(fixture.backend.isCapturing)
        XCTAssertEqual(fixture.backend.stopCount, 1)
    }

    func testCancelCannotDeleteCaptureAfterStopWinsFinalization() async throws {
        let fixture = try makeFixture(suspendFinish: true)
        defer { fixture.removeFiles() }
        try await fixture.recorder.start(
            configuration: MeetingCaptureConfiguration(meetingID: UUID(), maximumDuration: 60)
        )

        let stopTask = Task { try await fixture.recorder.stop() }
        await fixture.writers.waitUntilFinishSuspended()
        let cancelTask = Task { await fixture.recorder.cancel() }
        await fixture.writers.resumeFinish()
        let capture = try await stopTask.value
        await cancelTask.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.microphoneURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.systemAudioURL.path))
    }

    private func makeFixture(
        availableBytes: Int64 = 10_000_000_000,
        failingTrackName: String? = nil,
        suspendStart: Bool = false,
        suspendFinish: Bool = false
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperMeetingTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(rootURL: root)
        let backend = FakeMeetingCaptureBackend(suspendStart: suspendStart)
        let writers = FakeMeetingWriterRegistry(
            failingTrackName: failingTrackName,
            suspendFinish: suspendFinish
        )
        let scheduler = FakeMeetingDeadlineScheduler()
        let clock = TestClock()
        let recorder = ScreenCaptureMeetingRecorder(
            paths: paths,
            backend: backend,
            diskSpaceMonitor: DiskSpaceMonitor { _ in availableBytes },
            writerFactory: { writers.makeWriter(outputURL: $0) },
            deadlineScheduler: scheduler,
            now: { Date(timeIntervalSince1970: 1_000) },
            uptime: { clock.value }
        )
        return Fixture(
            root: root,
            paths: paths,
            backend: backend,
            writers: writers,
            scheduler: scheduler,
            clock: clock,
            recorder: recorder
        )
    }
}

private struct Fixture {
    let root: URL
    let paths: AppPaths
    let backend: FakeMeetingCaptureBackend
    let writers: FakeMeetingWriterRegistry
    let scheduler: FakeMeetingDeadlineScheduler
    let clock: TestClock
    let recorder: ScreenCaptureMeetingRecorder

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FakeMeetingCaptureBackend: MeetingCaptureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let startGate: TestAsyncGate?
    private let stopSignal = TestSignal()
    private var _startCount = 0
    private var _stopCount = 0
    private var _microphoneDeviceID: String?
    private var _isCapturing = false
    private var sampleHandler: (@Sendable (MeetingAudioSource, CMSampleBuffer) -> Void)?
    private var interruptionHandler: (@Sendable (MeetingAudioSource) -> Void)?

    init(suspendStart: Bool) {
        startGate = suspendStart ? TestAsyncGate() : nil
    }

    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }
    var microphoneDeviceID: String? { lock.withLock { _microphoneDeviceID } }
    var isCapturing: Bool { lock.withLock { _isCapturing } }

    func start(
        microphoneDeviceID: String?,
        sampleHandler: @escaping @Sendable (MeetingAudioSource, CMSampleBuffer) -> Void,
        interruptionHandler: @escaping @Sendable (MeetingAudioSource) -> Void
    ) async throws {
        lock.withLock {
            _startCount += 1
            _microphoneDeviceID = microphoneDeviceID
            self.sampleHandler = sampleHandler
            self.interruptionHandler = interruptionHandler
        }
        await startGate?.wait()
        lock.withLock { _isCapturing = true }
    }

    func stop() async {
        lock.withLock {
            _stopCount += 1
            _isCapturing = false
        }
        await stopSignal.signal()
    }

    func waitUntilStartSuspended() async {
        await startGate?.waitUntilSuspended()
    }

    func resumeStart() async {
        await startGate?.open()
    }

    func waitUntilStopCalled() async {
        await stopSignal.wait()
    }

    func emit(_ sampleBuffer: CMSampleBuffer, from source: MeetingAudioSource) {
        lock.withLock { sampleHandler }?(source, sampleBuffer)
    }

    func interrupt(_ source: MeetingAudioSource) {
        lock.withLock { interruptionHandler }?(source)
    }
}

private final class FakeMeetingWriterRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private let failingTrackName: String?
    private let finishGate: TestAsyncGate?
    private var _createdURLs: [URL] = []
    private var _finishCount = 0
    private var _cancelCount = 0
    private var appendCounts: [String: Int] = [:]

    init(failingTrackName: String?, suspendFinish: Bool) {
        self.failingTrackName = failingTrackName
        finishGate = suspendFinish ? TestAsyncGate() : nil
    }

    var createdURLs: [URL] { lock.withLock { _createdURLs } }
    var finishCount: Int { lock.withLock { _finishCount } }
    var cancelCount: Int { lock.withLock { _cancelCount } }

    func makeWriter(outputURL: URL) -> any MeetingTrackWriter {
        lock.withLock { _createdURLs.append(outputURL) }
        return FakeMeetingTrackWriter(outputURL: outputURL, registry: self)
    }

    fileprivate func finish(outputURL: URL) async throws -> URL {
        lock.withLock { _finishCount += 1 }
        await finishGate?.wait()
        return try lock.withLock {
            if outputURL.lastPathComponent == failingTrackName {
                throw SampleBufferAudioWriterError.cannotFinish
            }
            try Data([1, 2, 3]).write(to: outputURL)
            return outputURL
        }
    }

    fileprivate func cancel() {
        lock.withLock { _cancelCount += 1 }
    }

    fileprivate func append(outputURL: URL) {
        lock.withLock {
            appendCounts[outputURL.lastPathComponent, default: 0] += 1
        }
    }

    func appendCount(for trackName: String) -> Int {
        lock.withLock { appendCounts[trackName, default: 0] }
    }

    func waitUntilFinishSuspended() async {
        await finishGate?.waitUntilSuspended()
    }

    func resumeFinish() async {
        await finishGate?.open()
    }
}

private final class FakeMeetingTrackWriter: MeetingTrackWriter, @unchecked Sendable {
    private let outputURL: URL
    private let registry: FakeMeetingWriterRegistry

    init(outputURL: URL, registry: FakeMeetingWriterRegistry) {
        self.outputURL = outputURL
        self.registry = registry
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        registry.append(outputURL: outputURL)
    }
    func finish() async throws -> URL { try await registry.finish(outputURL: outputURL) }
    func cancel() { registry.cancel() }
}

private final class FakeMeetingDeadlineScheduler: MeetingDeadlineScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var scheduledInterval: TimeInterval?
    private var action: (@Sendable () -> Void)?

    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> any MeetingDeadline {
        lock.withLock {
            scheduledInterval = interval
            self.action = action
        }
        return FakeMeetingDeadline()
    }

    func fire() {
        lock.withLock { action }?()
    }
}

private final class FakeMeetingDeadline: MeetingDeadline, @unchecked Sendable {
    func cancel() {}
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: TimeInterval = 0

    var value: TimeInterval {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private actor TestAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionObservers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            let observers = suspensionObservers
            suspensionObservers.removeAll()
            observers.forEach { $0.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { suspensionObservers.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor TestSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
