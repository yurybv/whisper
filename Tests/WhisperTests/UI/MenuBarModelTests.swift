import XCTest
@testable import Whisper

final class MenuBarModelTests: XCTestCase {
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
}
