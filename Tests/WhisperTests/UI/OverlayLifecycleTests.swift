import AppKit
import XCTest
@testable import Whisper

@MainActor
final class OverlayLifecycleTests: XCTestCase {
    func testHUDPanelIsNonactivatingAndNeverKey() {
        let panel = DictationHUDPanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testHUDPresentationsAlwaysIncludeTextAndIcon() {
        let presentations = [
            DictationHUDPresentation(state: .recording(modeName: "Default")),
            DictationHUDPresentation(state: .transcribing),
            DictationHUDPresentation(state: .transforming),
            DictationHUDPresentation(state: .inserting),
            DictationHUDPresentation(state: .completed(.insertedDirectly)),
            DictationHUDPresentation(
                state: .failed(
                    message: "Network unavailable",
                    textOnClipboard: false,
                    recovery: .retryOrDiscard
                )
            ),
            DictationHUDPresentation(status: .cancelled),
        ]

        XCTAssertTrue(presentations.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        XCTAssertEqual(presentations.first?.detail, "Default")
    }

    func testClipboardOnlyCompletionExplainsManualPaste() {
        let presentation = DictationHUDPresentation(
            state: .completed(.copiedForManualPaste)
        )

        XCTAssertEqual(presentation.title, "Paste manually")
        XCTAssertTrue(presentation.detail.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertEqual(presentation.accent, .warning)
    }

    func testHUDFrameIsBottomCenteredInsideVisibleScreen() {
        let frame = DictationHUDController.frame(
            panelSize: NSSize(width: 360, height: 92),
            visibleFrame: NSRect(x: 100, y: 50, width: 1_200, height: 800)
        )

        XCTAssertEqual(frame.origin.x, 520)
        XCTAssertEqual(frame.origin.y, 74)
    }

    func testModeSwitcherPanelCanBecomeKey() {
        let panel = ModeSwitcherPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testModeSwitcherLifecycleRestoresPreviousApplicationOnClose() {
        let panel = FakeModeSwitcherPanel()
        let application = FakeRestorableApplication()
        let lifecycle = ModeSwitcherPanelLifecycle(
            panel: panel,
            frontmostApplication: { application }
        )

        lifecycle.show()
        lifecycle.close()

        XCTAssertEqual(panel.presentCount, 1)
        XCTAssertEqual(panel.dismissCount, 1)
        XCTAssertEqual(application.restoreCount, 1)
    }

    func testRepeatedShowDoesNotReplaceApplicationToRestore() {
        let panel = FakeModeSwitcherPanel()
        let firstApplication = FakeRestorableApplication()
        let secondApplication = FakeRestorableApplication()
        var applications: [FakeRestorableApplication] = [firstApplication, secondApplication]
        let lifecycle = ModeSwitcherPanelLifecycle(
            panel: panel,
            frontmostApplication: { applications.removeFirst() }
        )

        lifecycle.show()
        lifecycle.show()
        lifecycle.close()

        XCTAssertEqual(firstApplication.restoreCount, 1)
        XCTAssertEqual(secondApplication.restoreCount, 0)
        XCTAssertEqual(applications.count, 1)
    }
}

@MainActor
private final class FakeModeSwitcherPanel: ModeSwitcherPanelPresenting {
    var isVisible = false
    private(set) var presentCount = 0
    private(set) var dismissCount = 0

    func present() {
        isVisible = true
        presentCount += 1
    }

    func dismiss() {
        isVisible = false
        dismissCount += 1
    }
}

@MainActor
private final class FakeRestorableApplication: ApplicationRestoring {
    private(set) var restoreCount = 0

    @discardableResult
    func restoreActivation() -> Bool {
        restoreCount += 1
        return true
    }
}
