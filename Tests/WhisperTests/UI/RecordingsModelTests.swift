import AppKit
import SwiftUI
import XCTest
@testable import Whisper

@MainActor
final class RecordingsModelTests: XCTestCase {
    func testRecordingPreferencesPersistAndDefaultToApprovedValues() {
        let defaults = isolatedDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.recordingInstructions, AppSettings.defaultRecordingInstructions)
        XCTAssertNil(store.recordingResultLanguage)

        store.recordingInstructions = "List decisions only."
        store.recordingResultLanguage = "Russian"

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.recordingInstructions, "List decisions only.")
        XCTAssertEqual(reloaded.recordingResultLanguage, "Russian")
    }

    func testStartSnapshotsCurrentSettingsAndSelectedMicrophone() async throws {
        let fixture = Fixture()
        fixture.model.instructions = "Summarize decisions."
        fixture.model.resultLanguage = .russian

        await fixture.model.toggleRecording()

        XCTAssertEqual(fixture.actions.starts.count, 1)
        XCTAssertEqual(fixture.actions.starts.first?.instructions, "Summarize decisions.")
        XCTAssertEqual(fixture.actions.starts.first?.resultLanguage, "Russian")
        XCTAssertEqual(fixture.actions.starts.first?.microphoneID, "studio-mic")
        guard case .recording = fixture.model.state else {
            return XCTFail("Expected recording state")
        }
    }

    func testBlockedDiskAndMissingPermissionExposeSpecificRecovery() async {
        let blocked = Fixture(diskState: .blocked(availableBytes: 1_500_000_000))
        XCTAssertFalse(blocked.model.hasActionError)

        await blocked.model.toggleRecording()

        XCTAssertTrue(blocked.model.statusMessage.localizedCaseInsensitiveContains("2 GB"))
        XCTAssertTrue(blocked.model.hasActionError)
        XCTAssertTrue(blocked.actions.starts.isEmpty)

        let deniedSettings = FakeRecordingSettings()
        deniedSettings.permissions = PermissionSnapshot(
            microphone: .granted,
            screenRecording: .denied,
            accessibility: .granted,
            inputMonitoring: .granted
        )
        let denied = Fixture(settings: deniedSettings)
        XCTAssertFalse(denied.model.hasActionError)

        await denied.model.toggleRecording()

        XCTAssertTrue(denied.model.statusMessage.localizedCaseInsensitiveContains("Screen Recording"))
        XCTAssertTrue(denied.model.hasActionError)
        XCTAssertTrue(denied.actions.starts.isEmpty)
    }

    func testLiveLevelsTimerAndStopStateRemainInOwnedModel() async {
        let fixture = Fixture()
        fixture.model.consume(.recording(meetingID: fixture.actions.meetingID))
        fixture.model.consume(
            MeetingAudioLevels(microphone: 0.7, systemAudio: 0.4, elapsedTime: 2_238)
        )

        XCTAssertEqual(fixture.model.elapsedLabel, "00:37:18")
        XCTAssertEqual(fixture.model.microphoneLevel, 0.7)
        XCTAssertEqual(fixture.model.systemAudioLevel, 0.4)

        await fixture.model.toggleRecording()

        XCTAssertEqual(fixture.actions.stopCount, 1)
        guard case .finalizing = fixture.model.state else {
            return XCTFail("Expected finalizing state")
        }
    }

    func testCancelReturnsToIdleAndInvokesCoordinator() async {
        let fixture = Fixture()
        fixture.model.consume(.recording(meetingID: fixture.actions.meetingID))

        let cancelled = await fixture.model.cancelRecording()

        XCTAssertTrue(cancelled)
        XCTAssertEqual(fixture.actions.cancelCount, 1)
        XCTAssertEqual(fixture.model.state, .idle)
    }

    func testStopFailureRestoresRecordingSoOwnerCanRetry() async {
        let fixture = Fixture(stopError: PersistenceError.meetingNotFound)
        fixture.model.consume(.recording(meetingID: fixture.actions.meetingID))

        await fixture.model.toggleRecording()

        guard case .recording = fixture.model.state else {
            return XCTFail("Expected recording state to remain retryable")
        }
        XCTAssertFalse(fixture.model.statusMessage.isEmpty)
    }

    func testProcessingStateCannotStartAnotherCapture() async {
        let fixture = Fixture()
        fixture.model.consume(.processing(meetingID: fixture.actions.meetingID))

        await fixture.model.toggleRecording()

        XCTAssertTrue(fixture.actions.starts.isEmpty)
        XCTAssertEqual(fixture.model.state, .processing(meetingID: fixture.actions.meetingID))
    }

    func testRetryableFailureExposesRetryAndKeepsOriginalMeeting() async {
        let fixture = Fixture()
        fixture.model.consume(
            MeetingRuntimeState.failed(
                meetingID: fixture.actions.meetingID,
                message: "Check your network connection, then retry.",
                retryable: true
            )
        )

        XCTAssertTrue(fixture.model.canRetryProcessing)
        XCTAssertFalse(fixture.model.canToggleRecording)
        await fixture.model.retryProcessing()

        XCTAssertEqual(fixture.actions.retriedMeetingIDs, [fixture.actions.meetingID])
    }

    func testActiveCaptureIgnoresRuntimeEventsFromAnotherMeeting() {
        let fixture = Fixture()
        let activeID = fixture.actions.meetingID
        fixture.model.consume(.recording(meetingID: activeID))

        fixture.model.consume(.ready(meetingID: UUID()))

        XCTAssertEqual(fixture.model.state, .recording(meetingID: activeID))
        fixture.model.consume(.finalizing(meetingID: activeID))
        XCTAssertEqual(fixture.model.state, .finalizing(meetingID: activeID))
    }

    func testRuntimeStateSequenceExposesFinalizingProgressAndReady() {
        let fixture = Fixture()
        let id = fixture.actions.meetingID

        fixture.model.consume(.finalizing(meetingID: id))
        XCTAssertEqual(fixture.model.statusTitle, "Finalizing")
        fixture.model.consume(.transcribing(meetingID: id, completed: 1, total: 2))
        XCTAssertEqual(fixture.model.statusMessage, "Transcribing 1 of 2 chunks.")
        fixture.model.consume(.ready(meetingID: id))
        XCTAssertEqual(fixture.model.statusTitle, "Ready")
    }

    func testIdleAndActiveViewsProduceDistinctOffscreenSnapshots() throws {
        let fixture = Fixture()
        let idle = try snapshot(of: RecordingsView(model: fixture.model))
        let activeFixture = Fixture()
        activeFixture.model.consume(.recording(meetingID: activeFixture.actions.meetingID))
        activeFixture.model.consume(
            MeetingAudioLevels(microphone: 0.7, systemAudio: 0.45, elapsedTime: 2_238)
        )
        let active = try snapshot(of: RecordingsView(model: activeFixture.model))

        XCTAssertGreaterThan(idle.count, 20_000)
        XCTAssertGreaterThan(active.count, 20_000)
        XCTAssertNotEqual(idle, active)
        let idleAttachment = XCTAttachment(
            data: idle,
            uniformTypeIdentifier: "public.png"
        )
        idleAttachment.name = "Recordings idle"
        idleAttachment.lifetime = .keepAlways
        add(idleAttachment)
        let activeAttachment = XCTAttachment(
            data: active,
            uniformTypeIdentifier: "public.png"
        )
        activeAttachment.name = "Recordings active 00-37-18"
        activeAttachment.lifetime = .keepAlways
        add(activeAttachment)
    }

    private func snapshot<Content: View>(of view: Content) throws -> Data {
        let size = NSSize(width: 1_040, height: 800)
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "RecordingsModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@MainActor
private struct Fixture {
    let settings: FakeRecordingSettings
    let actions = RecordingActionSpy()
    let model: RecordingsModel

    init(
        settings: FakeRecordingSettings = FakeRecordingSettings(),
        diskState: DiskSpaceMonitor.State = .ready(availableBytes: 10_000_000_000),
        stopError: Error? = nil
    ) {
        self.settings = settings
        let defaults = UserDefaults(suiteName: "RecordingsModelFixture-\(UUID().uuidString)")!
        let store = AppSettingsStore(defaults: defaults)
        model = RecordingsModel(
            settingsStore: store,
            settings: settings,
            diskState: { diskState },
            start: { [actions] title, instructions, resultLanguage, microphoneID in
                actions.starts.append(
                    .init(
                        title: title,
                        instructions: instructions,
                        resultLanguage: resultLanguage,
                        microphoneID: microphoneID
                    )
                )
                return actions.meetingID
            },
            stop: { [actions] in
                actions.stopCount += 1
                if let stopError { throw stopError }
            },
            cancel: { [actions] in actions.cancelCount += 1; return true },
            retry: { [actions] meetingID in actions.retriedMeetingIDs.append(meetingID) },
            now: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )
    }

}

@MainActor
private final class FakeRecordingSettings: RecordingSettingsProviding {
    var microphones = [MicrophoneDevice(id: "studio-mic", name: "Studio Mic")]
    var selectedMicrophoneID: String? = "studio-mic"
    var shortcuts = AppSettings.defaults.shortcuts
    var permissions = PermissionSnapshot(
        microphone: .granted,
        screenRecording: .granted,
        accessibility: .granted,
        inputMonitoring: .granted
    )

    var selectedMicrophoneName: String { "Studio Mic" }
    func refresh() {}
    func selectMicrophone(_ id: String?) { selectedMicrophoneID = id }
    func openPermissionSettings(_ kind: PermissionKind) {}
}

@MainActor
private final class RecordingActionSpy {
    struct Start: Equatable {
        let title: String
        let instructions: String
        let resultLanguage: String?
        let microphoneID: String?
    }

    let meetingID = UUID()
    var starts: [Start] = []
    var stopCount = 0
    var cancelCount = 0
    var retriedMeetingIDs: [UUID] = []
}
