import XCTest

final class RecordingsUITests: XCTestCase {
    @MainActor
    func testIdleRecordingComposition() throws {
        let app = launch()

        XCTAssertTrue(app.staticTexts["Recordings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ready to record"].exists)
        XCTAssertTrue(app.buttons["Start Recording"].exists)
        XCTAssertTrue(app.staticTexts["System Audio"].exists)
        XCTAssertTrue(app.staticTexts["Microphone"].exists)
        XCTAssertTrue(app.staticTexts["Processing Instructions"].exists)
        XCTAssertTrue(app.staticTexts["Result Language"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    @MainActor
    func testActiveRecordingShowsTimerMetersAndStop() throws {
        let app = launch(extraArguments: ["--recording-active"])

        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["00:37:18"].exists)
        XCTAssertTrue(app.buttons["Stop Recording"].exists)
        XCTAssertTrue(app.buttons["Cancel Recording"].exists)
        XCTAssertTrue(app.staticTexts["Microphone"].exists)
        XCTAssertTrue(app.staticTexts["System"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    @MainActor
    func testLowDiskBlocksStartWithExactThreshold() throws {
        let app = launch(extraArguments: ["--recording-low-disk"])

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@",
            "2 GB"
        )).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start Recording"].isEnabled)
    }

    @MainActor
    func testRecordingFlowShowsFinalizingTranscriptionProgressAndReady() throws {
        let app = launch()

        app.buttons["Start Recording"].click()
        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["00:37:18"].waitForExistence(timeout: 3))

        app.buttons["Stop Recording"].click()
        XCTAssertTrue(app.staticTexts["Finalizing"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Transcribing 1 of 2 chunks."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--permissions-granted",
            "--api-key-state", "valid",
            "--ui-destination", "recordings",
        ] + extraArguments
        app.launch()
        return app
    }
}
