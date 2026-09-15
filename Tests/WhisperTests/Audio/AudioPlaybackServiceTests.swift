import Foundation
import XCTest
@testable import Whisper

@MainActor
final class AudioPlaybackServiceTests: XCTestCase {
    func testAVTransportPreparesRealSilentMixAndStops() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperPlaybackSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("first.m4a")
        let secondURL = root.appendingPathComponent("second.m4a")
        for url in [firstURL, secondURL] {
            let writer = SampleBufferAudioWriter(outputURL: url)
            for index in 0..<3 {
                try writer.append(
                    makeTestAudioSampleBuffer(
                        presentationSeconds: 10 + (Double(index) * 0.1),
                        amplitude: 0
                    )
                )
            }
            _ = try await writer.finish()
        }
        let transport = AVPlayerPlaybackTransport()

        try await transport.play(
            AudioPlaybackPlan(
                source: .mix,
                tracks: [
                    AudioPlaybackTrack(url: firstURL, offset: 0),
                    AudioPlaybackTrack(url: secondURL, offset: 0.05),
                ]
            )
        )
        transport.stop()

        XCTAssertGreaterThan(try Data(contentsOf: firstURL).count, 0)
        XCTAssertGreaterThan(try Data(contentsOf: secondURL).count, 0)
    }

    func testAvailableSourcesRequireOwnedExistingFiles() throws {
        let fixture = try PlaybackFixture()
        defer { fixture.cleanup() }
        try Data("microphone".utf8).write(to: fixture.microphoneURL)
        try Data("system".utf8).write(to: fixture.systemURL)

        XCTAssertEqual(
            fixture.service.availableSources(for: fixture.meeting),
            [.mix, .microphone, .systemAudio]
        )

        let unsafe = fixture.meetingCopy(
            microphoneRelativePath: "meeting-\(UUID().uuidString)/microphone.m4a"
        )
        XCTAssertEqual(fixture.service.availableSources(for: unsafe), [.systemAudio])
    }

    func testPlayBuildsOffsetMixWithoutChangingSourceFiles() async throws {
        let fixture = try PlaybackFixture()
        defer { fixture.cleanup() }
        let microphone = Data("microphone".utf8)
        let system = Data("system".utf8)
        try microphone.write(to: fixture.microphoneURL)
        try system.write(to: fixture.systemURL)

        try await fixture.service.play(meeting: fixture.meeting, source: .mix)

        let plan = try XCTUnwrap(fixture.transport.plans.last)
        XCTAssertEqual(plan.source, .mix)
        XCTAssertEqual(plan.tracks.map(\.offset), [0.25, 0.75])
        XCTAssertEqual(try Data(contentsOf: fixture.microphoneURL), microphone)
        XCTAssertEqual(try Data(contentsOf: fixture.systemURL), system)
    }

    func testUnavailableSourceDoesNotReachTransportAndStopIsForwarded() async throws {
        let fixture = try PlaybackFixture()
        defer { fixture.cleanup() }

        do {
            try await fixture.service.play(meeting: fixture.meeting, source: .mix)
            XCTFail("Expected unavailable playback source")
        } catch {
            XCTAssertEqual(error as? AudioPlaybackError, .sourceUnavailable)
        }
        XCTAssertTrue(fixture.transport.plans.isEmpty)

        fixture.service.stop()
        XCTAssertEqual(fixture.transport.stopCount, 1)
    }
}

@MainActor
private final class RecordingPlaybackTransport: AudioPlaybackTransport {
    var plans: [AudioPlaybackPlan] = []
    var stopCount = 0

    func play(_ plan: AudioPlaybackPlan) async throws { plans.append(plan) }
    func stop() { stopCount += 1 }
}

@MainActor
private final class PlaybackFixture {
    let root: URL
    let paths: AppPaths
    let transport = RecordingPlaybackTransport()
    let service: AudioPlaybackService
    let meeting: MeetingSnapshot
    let microphoneURL: URL
    let systemURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperPlayback-\(UUID().uuidString)", isDirectory: true)
        paths = try AppPaths(rootURL: root)
        let id = UUID()
        let directory = try paths.recordingDirectory(for: id)
        microphoneURL = directory.appendingPathComponent("microphone.m4a")
        systemURL = directory.appendingPathComponent("system.m4a")
        meeting = MeetingSnapshot(
            id: id,
            title: "Planning",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            endedAt: Date(timeIntervalSinceReferenceDate: 160),
            duration: 60,
            status: .ready,
            progressCompleted: 2,
            progressTotal: 2,
            instructionsSnapshot: "Summarize",
            resultLanguage: nil,
            microphoneRelativePath: try paths.relativeRecordingPath(for: microphoneURL, meetingID: id),
            systemAudioRelativePath: try paths.relativeRecordingPath(for: systemURL, meetingID: id),
            microphoneStartOffset: 0.25,
            systemAudioStartOffset: 0.75,
            processedText: "Notes",
            errorMessage: nil,
            failureKind: nil,
            retryStage: nil
        )
        service = AudioPlaybackService(paths: paths, transport: transport)
    }

    func meetingCopy(microphoneRelativePath: String) -> MeetingSnapshot {
        MeetingSnapshot(
            id: meeting.id,
            title: meeting.title,
            startedAt: meeting.startedAt,
            endedAt: meeting.endedAt,
            duration: meeting.duration,
            status: meeting.status,
            progressCompleted: meeting.progressCompleted,
            progressTotal: meeting.progressTotal,
            instructionsSnapshot: meeting.instructionsSnapshot,
            resultLanguage: meeting.resultLanguage,
            microphoneRelativePath: microphoneRelativePath,
            systemAudioRelativePath: meeting.systemAudioRelativePath,
            microphoneStartOffset: meeting.microphoneStartOffset,
            systemAudioStartOffset: meeting.systemAudioStartOffset,
            processedText: meeting.processedText,
            errorMessage: meeting.errorMessage,
            failureKind: meeting.failureKind,
            retryStage: meeting.retryStage
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
