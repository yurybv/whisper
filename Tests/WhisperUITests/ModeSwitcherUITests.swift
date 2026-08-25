import XCTest

final class ModeSwitcherUITests: XCTestCase {
    func testKeyboardNavigationActivatesModeAndClosesPalette() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke-mode-switcher"]
        app.launch()

        let search = app.textFields["Search modes"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Default"].exists)

        search.typeKey(.downArrow, modifierFlags: [])
        search.typeKey(.return, modifierFlags: [])

        XCTAssertFalse(search.waitForExistence(timeout: 1))
    }

    func testEscapeClosesPaletteWithoutTerminatingUtility() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke-mode-switcher"]
        app.launch()

        let search = app.textFields["Search modes"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))

        search.typeKey(.escape, modifierFlags: [])

        XCTAssertFalse(search.waitForExistence(timeout: 1))
        XCTAssertEqual(app.state, .runningBackground)
    }
}
