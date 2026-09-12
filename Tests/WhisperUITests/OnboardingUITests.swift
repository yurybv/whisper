import XCTest

final class OnboardingUITests: XCTestCase {
    func testFirstLaunchCompletesFourStepsAndCanPreviewFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--onboarding-incomplete", "--permissions-granted", "--api-key-state", "valid"]
        app.launch()
        let key = app.secureTextFields["OpenAI API key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.click()
        key.typeText("sk-test-onboarding-fixture")
        app.buttons["Save and Test"].click()
        XCTAssertTrue(app.staticTexts["Connection verified"].waitForExistence(timeout: 3))
        for title in ["Microphone access", "Screen Recording access", "Accessibility access", "Ready"] {
            app.buttons["Continue"].click()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))
        }
        XCTAssertTrue(app.staticTexts["Right Option"].exists)
        XCTAssertTrue(app.staticTexts["Control-Command-M"].exists)
        XCTAssertTrue(app.staticTexts["Command-Shift-R"].exists)
        app.buttons["Open Home"].click()
        XCTAssertTrue(app.staticTexts["Welcome to Whisper"].waitForExistence(timeout: 2))
        app.buttons["Settings"].click()
        app.buttons["Preview Setup"].click()
        XCTAssertTrue(key.waitForExistence(timeout: 2))
        app.buttons["Close Setup"].click()
        XCTAssertTrue(app.buttons["Preview Setup"].waitForExistence(timeout: 2))
    }

    func testDeniedPermissionsAndInvalidKeyDoNotTrapUserInSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--onboarding-incomplete", "--api-key-state", "invalid"]
        app.launch()
        let key = app.secureTextFields["OpenAI API key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.click()
        key.typeText("sk-test-invalid")
        app.buttons["Save and Test"].click()
        XCTAssertTrue(app.staticTexts["Connection could not be verified. Check your key and network, then try again."].waitForExistence(timeout: 3))
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Microphone access"].exists)
        XCTAssertTrue(app.buttons["Open System Settings"].exists)
        app.buttons["Continue"].click()
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Input Monitoring"].exists)
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        XCTAssertTrue(app.buttons["Open Input Monitoring Settings"].isHittable)
        app.buttons["Open Input Monitoring Settings"].click()
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
        XCTAssertTrue(app.buttons["Relaunch Whisper"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Relaunch Whisper"].isHittable)
        app.buttons["Continue"].click()
        XCTAssertTrue(app.staticTexts["Setup needs attention"].exists)
        XCTAssertTrue(app.buttons["Repair Input Monitoring"].exists)
        app.buttons["Repair Screen Recording"].click()
        XCTAssertTrue(app.buttons["Relaunch Whisper"].waitForExistence(timeout: 2))
        app.buttons["Open Home"].click()
        XCTAssertTrue(app.staticTexts["Welcome to Whisper"].waitForExistence(timeout: 2))
    }
}
