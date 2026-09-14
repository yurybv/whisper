import XCTest

@MainActor
final class AccessibilityUITests: XCTestCase {
    func testPrimaryNavigationAndModeActionsUsePracticalTargets() {
        let app = launchCompletedApp(destination: "modes")

        for destination in ["Home", "Modes", "Recordings", "History", "Settings"] {
            let button = app.buttons[destination]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing \(destination) navigation button")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(destination) target is too short")
        }

        let actions = app.menuButtons["Actions for Default"]
        XCTAssertTrue(actions.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(actions.frame.width, 44)
        XCTAssertGreaterThanOrEqual(actions.frame.height, 44)
    }

    func testHomeDoesNotExposeDecorativeStatusSymbols() {
        let app = launchCompletedApp()

        XCTAssertTrue(app.staticTexts["Ready to dictate"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.images["Selected"].exists)
        XCTAssertTrue(app.staticTexts["Saved in Keychain"].exists)
        XCTAssertTrue(app.staticTexts["Permissions"].exists)
    }

    func testPrimaryScreensExposeTextForImportantStates() {
        let settings = launchCompletedApp(
            destination: "settings",
            extraArguments: ["--connection-result", "testing", "--shortcut-conflict"]
        )

        XCTAssertTrue(settings.staticTexts["That shortcut is already used by Record Meeting."].exists)
        XCTAssertTrue(settings.staticTexts["Testing connection…"].waitForExistence(timeout: 2))
        settings.terminate()

        let failedSettings = launchCompletedApp(
            destination: "settings",
            extraArguments: ["--connection-result", "failed"]
        )
        XCTAssertTrue(
            failedSettings.staticTexts[
                "Connection could not be verified. Check your key and network, then try again."
            ].waitForExistence(timeout: 3)
        )
        failedSettings.terminate()

        let home = launchCompletedApp(destination: "home", permissionsGranted: false)
        XCTAssertTrue(home.staticTexts["Dictation needs microphone access"].waitForExistence(timeout: 3))
        XCTAssertTrue(home.staticTexts["No history yet"].exists)
        home.terminate()

        let modes = launchCompletedApp(destination: "modes")
        XCTAssertFalse(modes.textFields["Mode name"].isEnabled)
        XCTAssertFalse(modes.popUpButtons["Input language"].isEnabled)
        XCTAssertTrue(modes.staticTexts["Active mode"].exists)
    }

    func testPrimaryScreensPassSystemAccessibilityAudit() throws {
        let screens = [
            (destination: "home", marker: "Ready to dictate"),
            (destination: "modes", marker: "Modes"),
            (destination: "settings", marker: "Settings")
        ]
        let auditTypes: XCUIAccessibilityAuditType = [
            .action,
            .elementDetection,
            .parentChild,
            .sufficientElementDescription
        ]

        for screen in screens {
            let app = launchCompletedApp(destination: screen.destination)
            XCTAssertTrue(app.staticTexts[screen.marker].waitForExistence(timeout: 3))
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                self.isKnownSwiftUIAuditIssue(issue)
            }
            app.terminate()
        }
    }

    func testLongModeContentRemainsReachableAtMinimumWindowSize() {
        let longModeName = "Long mode 12345 67890 12345 67890 12345 67890"
        let app = launchCompletedApp(
            destination: "modes",
            extraArguments: ["--long-content"]
        )

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(window.frame.width, 1_120)
        XCTAssertGreaterThanOrEqual(window.frame.height, 760)
        XCTAssertTrue(app.buttons["Mode row \(longModeName)"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuButtons["Actions for \(longModeName)"].exists)
    }

    private func launchCompletedApp(
        destination: String? = nil,
        permissionsGranted: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--api-key-state", "valid"
        ]
        if permissionsGranted {
            app.launchArguments.append("--permissions-granted")
        }
        if let destination {
            app.launchArguments += ["--ui-destination", destination]
        }
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    private func isKnownSwiftUIAuditIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        let elementType = element.elementType

        if issue.auditType == .sufficientElementDescription {
            return element.label.isEmpty
                && (elementType == .group || elementType == .other || elementType == .touchBar)
        }
        if issue.auditType == .action {
            return elementType == .menuButton || elementType == .popUpButton
        }
        if issue.auditType == .parentChild {
            return elementType == .group && element.label.isEmpty
        }
        return false
    }
}
