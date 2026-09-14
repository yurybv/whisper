import XCTest

@MainActor
final class ModeSwitcherUITests: XCTestCase {
    func testKeyboardNavigationActivatesModeAndClosesPalette() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-smoke-mode-switcher"]
        app.launch()

        let search = app.textFields["Search modes"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout: 3))

        search.typeKey(.downArrow, modifierFlags: [])
        search.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
    }

    func testEscapeClosesPaletteWithoutTerminatingUtility() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-smoke-mode-switcher"]
        app.launch()

        let search = app.textFields["Search modes"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))

        search.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningBackground)
    }
}
