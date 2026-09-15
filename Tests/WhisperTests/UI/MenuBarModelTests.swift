import XCTest
@testable import Whisper

final class MenuBarModelTests: XCTestCase {
    func testIdleDoesNotHideShortcutPermissionFailure() {
        let failure = AppRuntimeDictationPresentation(state: .idle, shortcutFailure: "Repair keyboard access")
        XCTAssertEqual(failure.menuState, .error)
        XCTAssertEqual(failure.message, "Repair keyboard access")
        XCTAssertFalse(failure.blocksNewDictation, "Menu-bar dictation remains available")
        let recovered = AppRuntimeDictationPresentation(state: .idle, shortcutFailure: nil)
        XCTAssertEqual(recovered.menuState, .ready)
        XCTAssertNil(recovered.message)
    }

    func testDictationFeedbackTakesPriorityOverShortcutFailure() {
        let presentation = AppRuntimeDictationPresentation(
            state: .completed(.copiedForManualPaste), shortcutFailure: "Repair keyboard access")
        XCTAssertTrue(presentation.message?.contains("Paste manually") == true)
        XCTAssertEqual(presentation.menuState, .error)
    }

    func testMenuActionsMirrorGlobalShortcuts() {
        XCTAssertEqual(MenuBarCommand.startDictation.shortcutAction, .pushToTalk)
        XCTAssertEqual(MenuBarCommand.changeMode.shortcutAction, .changeMode)
        XCTAssertEqual(MenuBarCommand.recordMeeting.shortcutAction, .recordMeeting)
        XCTAssertNil(MenuBarCommand.recentHistory.shortcutAction)
        XCTAssertNil(MenuBarCommand.openMainWindow.shortcutAction)
        XCTAssertNil(MenuBarCommand.retryDictation.shortcutAction)
        XCTAssertNil(MenuBarCommand.discardDictation.shortcutAction)
    }

    func testEveryMenuBarStateHasTextAndIcon() {
        let states: [MenuBarState] = [.ready, .dictating, .recordingMeeting, .processing, .error]

        XCTAssertTrue(states.allSatisfy { !$0.label.isEmpty && !$0.systemImage.isEmpty })
    }

    @MainActor
    func testRecoveryActionsReflectRetryAndDiscardDisposition() {
        let viewModel = MenuBarViewModel()

        XCTAssertEqual(viewModel.dictationRecovery, .none)
        viewModel.dictationRecovery = .retryOrDiscard
        XCTAssertTrue(viewModel.dictationRecovery.canRetry)
        XCTAssertTrue(viewModel.dictationRecovery.canDiscard)
        viewModel.dictationRecovery = .discardOnly
        XCTAssertFalse(viewModel.dictationRecovery.canRetry)
        XCTAssertTrue(viewModel.dictationRecovery.canDiscard)
    }

    func testRuntimeProjectionKeepsRecoveryActionsAndManualPasteFeedback() {
        let failure = AppRuntimeDictationPresentation(
            state: .failed(
                message: "Check your network connection.",
                textOnClipboard: false,
                recovery: .retryOrDiscard
            )
        )
        let manualPaste = AppRuntimeDictationPresentation(
            state: .completed(.copiedForManualPaste)
        )

        XCTAssertEqual(failure.menuState, .error)
        XCTAssertEqual(failure.recovery, .retryOrDiscard)
        XCTAssertTrue(failure.blocksNewDictation)
        XCTAssertEqual(manualPaste.menuState, .ready)
        XCTAssertTrue(manualPaste.message?.contains("Paste manually") == true)
    }

    @MainActor
    func testMeetingTimerIsVisibleInStatusItemPresentation() {
        let viewModel = MenuBarViewModel(
            state: .recordingMeeting,
            message: "Recording 00:37:18"
        )

        XCTAssertEqual(viewModel.statusItemTitle, "00:37:18")
        viewModel.state = .ready
        XCTAssertEqual(viewModel.statusItemTitle, "")
    }

    @MainActor
    func testFeatureStartReservationRejectsMeetingDuringSuspendedDictationStart() async {
        let arbiter = CaptureStartArbiter()

        XCTAssertTrue(arbiter.reserve(.dictation))
        await Task.yield()
        XCTAssertFalse(arbiter.reserve(.meeting))
        arbiter.release(.dictation)
        XCTAssertTrue(arbiter.reserve(.meeting))
    }

    @MainActor
    func testMeetingStartGateRejectsRecordingsButtonWhileDictationIsActive() async {
        let arbiter = CaptureStartArbiter()
        let gate = MeetingStartGate(
            arbiter: arbiter,
            dictationState: { .recording(modeName: "Default") }
        )
        var didStart = false

        do {
            _ = try await gate.start {
                didStart = true
                return UUID()
            }
            XCTFail("Expected meeting start to be rejected")
        } catch {
            XCTAssertEqual(error as? CaptureStartError, .dictationActive)
        }

        XCTAssertFalse(didStart)
        XCTAssertTrue(arbiter.reserve(.meeting), "Rejected start must release its reservation")
    }
}
