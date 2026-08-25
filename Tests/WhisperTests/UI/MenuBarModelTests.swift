import XCTest
@testable import Whisper

final class MenuBarModelTests: XCTestCase {
    func testMenuActionsMirrorGlobalShortcuts() {
        XCTAssertEqual(MenuBarCommand.startDictation.shortcutAction, .pushToTalk)
        XCTAssertEqual(MenuBarCommand.changeMode.shortcutAction, .changeMode)
        XCTAssertEqual(MenuBarCommand.recordMeeting.shortcutAction, .recordMeeting)
        XCTAssertNil(MenuBarCommand.recentHistory.shortcutAction)
        XCTAssertNil(MenuBarCommand.openMainWindow.shortcutAction)
    }

    func testEveryMenuBarStateHasTextAndIcon() {
        let states: [MenuBarState] = [.ready, .dictating, .recordingMeeting, .processing, .error]

        XCTAssertTrue(states.allSatisfy { !$0.label.isEmpty && !$0.systemImage.isEmpty })
    }
}
