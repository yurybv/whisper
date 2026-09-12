import XCTest

@MainActor
final class ModesUITests: XCTestCase {
    func testCreatesActivatesDuplicatesRenamesAndDeletesCustomMode() {
        let app = launchCompletedApp()
        app.buttons["Modes"].click()

        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mode row Default"].exists)
        XCTAssertFalse(app.buttons["Delete Default"].exists)
        XCTAssertFalse(app.buttons["Rename Default"].exists)

        app.buttons["Create Mode"].click()
        let name = app.textFields["Mode name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        replaceText(in: name, with: "12345")
        let instructions = app.textViews["Custom instructions"]
        replaceText(in: instructions, with: "98765")
        app.popUpButtons["Input language"].click()
        app.menuItems["Russian"].click()
        app.buttons["Save Changes"].click()

        XCTAssertTrue(app.staticTexts["12345"].waitForExistence(timeout: 2))
        app.buttons["Activate Mode"].click()
        XCTAssertTrue(app.staticTexts["Active mode"].waitForExistence(timeout: 2))

        app.buttons["Duplicate Mode"].click()
        XCTAssertTrue(app.staticTexts["12345 Copy"].waitForExistence(timeout: 2))
        let duplicateName = app.textFields["Mode name"]
        replaceText(in: duplicateName, with: "67890")
        app.buttons["Save Changes"].click()
        XCTAssertTrue(app.staticTexts["67890"].waitForExistence(timeout: 2))

        app.buttons["Delete Mode"].click()
        let deletionSheet = app.sheets.firstMatch
        XCTAssertTrue(deletionSheet.waitForExistence(timeout: 2))
        XCTAssertTrue(deletionSheet.staticTexts["Delete 67890?"].exists)
        deletionSheet.buttons["Delete"].click()
        XCTAssertFalse(app.staticTexts["67890"].exists)
    }

    func testHomeAndSettingsExposeRequiredStateAndActions() {
        let app = launchCompletedApp()

        XCTAssertTrue(app.staticTexts["Ready to dictate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start Dictation"].exists)
        XCTAssertTrue(app.buttons["Change Mode"].exists)
        XCTAssertTrue(app.buttons["Record Meeting"].exists)
        XCTAssertTrue(app.staticTexts["Right Option"].exists)
        XCTAssertTrue(app.staticTexts["Control-Command-M"].exists)
        XCTAssertTrue(app.staticTexts["Command-Shift-R"].exists)

        app.buttons["Settings"].click()
        XCTAssertTrue(app.staticTexts["OpenAI API Key"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["••••••••••••"].exists)
        XCTAssertTrue(app.popUpButtons["Microphone"].exists)
        XCTAssertTrue(app.buttons["Record Change Mode shortcut"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Launch at Login"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Sound Effects"].exists)
        XCTAssertTrue(app.buttons["Open Screen Recording Settings"].exists)
    }

    private func launchCompletedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--permissions-granted",
            "--api-key-state", "valid"
        ]
        app.launch()
        return app
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        element.click()
        element.typeKey(.leftArrow, modifierFlags: .command)
        element.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        element.typeKey(.delete, modifierFlags: [])
        element.typeText(value)
        XCTAssertEqual(element.value as? String, value)
    }
}
