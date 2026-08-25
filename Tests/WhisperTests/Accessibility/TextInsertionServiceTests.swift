import ApplicationServices
import Foundation
import XCTest
@testable import Whisper

@MainActor
final class TextInsertionServiceTests: XCTestCase {
    func testCaptureReadsFrontmostApplicationBeforeFocusedElement() async throws {
        let events = EventLog()
        let element = AXUIElementCreateApplication(42)
        let workspace = FakeWorkspaceClient(
            application: WorkspaceApplication(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor"
            ),
            events: events
        )
        let accessibility = FakeAccessibilityClient(
            focusedElement: element,
            events: events
        )
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            events: events
        )

        let target = try await service.captureFocusedTarget()

        XCTAssertEqual(target.processIdentifier, 42)
        XCTAssertEqual(target.bundleIdentifier, "com.example.Editor")
        XCTAssertTrue(CFEqual(target.element, element))
        XCTAssertEqual(events.values, ["workspace.frontmost", "accessibility.focusedElement"])
    }

    func testDirectSelectedTextInsertionIsPreferred() async throws {
        let events = EventLog()
        let element = AXUIElementCreateApplication(42)
        let workspace = FakeWorkspaceClient(events: events)
        let accessibility = FakeAccessibilityClient(
            isTrusted: true,
            setSelectedTextResult: .success,
            events: events
        )
        let pasteboard = FakePasteboardRestorer(events: events)
        let eventPoster = FakePasteEventPoster(events: events)
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            events: events
        )

        let result = try await service.insert(
            "Final text",
            into: FocusedTarget(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                element: element
            )
        )

        XCTAssertEqual(result, .insertedDirectly)
        XCTAssertEqual(accessibility.insertedText, "Final text")
        XCTAssertEqual(events.values, ["accessibility.setSelectedText"])
        XCTAssertNil(pasteboard.currentText)
        XCTAssertEqual(eventPoster.postCount, 0)
    }

    func testUnsupportedAXInsertionFallsBackToPasteAndRestoresClipboardAfterDelay() async throws {
        let events = EventLog()
        let element = AXUIElementCreateApplication(42)
        let workspace = FakeWorkspaceClient(activationResult: true, events: events)
        let accessibility = FakeAccessibilityClient(
            isTrusted: true,
            setSelectedTextResult: .attributeUnsupported,
            events: events
        )
        let pasteboard = FakePasteboardRestorer(
            originalText: "Original clipboard",
            events: events
        )
        let eventPoster = FakePasteEventPoster(postResult: true, events: events)
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            events: events
        )

        let result = try await service.insert(
            "Final text",
            into: FocusedTarget(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                element: element
            )
        )

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(pasteboard.currentText, "Original clipboard")
        XCTAssertEqual(
            events.values,
            [
                "accessibility.setSelectedText",
                "workspace.activate:42",
                "pasteboard.place",
                "events.postPaste",
                "sleep",
                "pasteboard.restore"
            ]
        )
    }

    func testDeniedAccessibilityLeavesFinalTextOnClipboardForManualPaste() async throws {
        let events = EventLog()
        let workspace = FakeWorkspaceClient(events: events)
        let accessibility = FakeAccessibilityClient(isTrusted: false, events: events)
        let pasteboard = FakePasteboardRestorer(
            originalText: "Original clipboard",
            events: events
        )
        let eventPoster = FakePasteEventPoster(events: events)
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            events: events
        )

        let result = try await service.insert(
            "Final text",
            into: FocusedTarget(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                element: nil
            )
        )

        XCTAssertEqual(result, .copiedForManualPaste)
        XCTAssertEqual(pasteboard.currentText, "Final text")
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(eventPoster.postCount, 0)
        XCTAssertEqual(events.values, ["pasteboard.place"])
    }

    func testFailedPasteEventKeepsFinalTextOnClipboard() async throws {
        let events = EventLog()
        let workspace = FakeWorkspaceClient(activationResult: true, events: events)
        let accessibility = FakeAccessibilityClient(isTrusted: true, events: events)
        let pasteboard = FakePasteboardRestorer(
            originalText: "Original clipboard",
            events: events
        )
        let eventPoster = FakePasteEventPoster(postResult: false, events: events)
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            events: events
        )

        let result = try await service.insert(
            "Final text",
            into: FocusedTarget(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                element: nil
            )
        )

        XCTAssertEqual(result, .copiedForManualPaste)
        XCTAssertEqual(pasteboard.currentText, "Final text")
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(
            events.values,
            ["workspace.activate:42", "pasteboard.place", "events.postPaste"]
        )
    }

    func testFailedActivationKeepsFinalTextOnClipboardWithoutPostingPaste() async throws {
        let events = EventLog()
        let workspace = FakeWorkspaceClient(activationResult: false, events: events)
        let accessibility = FakeAccessibilityClient(isTrusted: true, events: events)
        let pasteboard = FakePasteboardRestorer(events: events)
        let eventPoster = FakePasteEventPoster(events: events)
        let service = makeService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            events: events
        )

        let result = try await service.insert(
            "Final text",
            into: FocusedTarget(
                processIdentifier: 42,
                bundleIdentifier: "com.example.Editor",
                element: nil
            )
        )

        XCTAssertEqual(result, .copiedForManualPaste)
        XCTAssertEqual(pasteboard.currentText, "Final text")
        XCTAssertEqual(eventPoster.postCount, 0)
        XCTAssertEqual(events.values, ["workspace.activate:42", "pasteboard.place"])
    }

    func testPasteboardRestorerRoundTripsEveryRepresentation() throws {
        let initialSnapshot = PasteboardSnapshot(
            items: [
                PasteboardItemSnapshot(
                    representations: [
                        "public.utf8-plain-text": Data("Original".utf8),
                        "public.html": Data("<b>Original</b>".utf8)
                    ]
                )
            ]
        )
        let client = FakePasteboardClient(snapshot: initialSnapshot)
        let restorer = PasteboardRestorer(client: client)

        let snapshot = try XCTUnwrap(restorer.placeTextPreservingCurrentContents("Final text"))
        XCTAssertEqual(client.currentText, "Final text")

        restorer.restore(snapshot)

        XCTAssertEqual(client.restoredSnapshot, initialSnapshot)
    }

    func testPasteboardRestorerRestoresSnapshotWhenReplacementWriteFails() {
        let initialSnapshot = PasteboardSnapshot(
            items: [
                PasteboardItemSnapshot(
                    representations: [
                        "public.utf8-plain-text": Data("Original".utf8)
                    ]
                )
            ]
        )
        let client = FakePasteboardClient(
            snapshot: initialSnapshot,
            writeResult: false
        )
        let restorer = PasteboardRestorer(client: client)

        XCTAssertNil(restorer.placeTextPreservingCurrentContents("Final text"))
        XCTAssertEqual(client.restoredSnapshot, initialSnapshot)
    }

    private func makeService(
        workspace: FakeWorkspaceClient = FakeWorkspaceClient(),
        accessibility: FakeAccessibilityClient = FakeAccessibilityClient(),
        pasteboard: FakePasteboardRestorer = FakePasteboardRestorer(),
        eventPoster: FakePasteEventPoster = FakePasteEventPoster(),
        events: EventLog
    ) -> AXTextInsertionService {
        AXTextInsertionService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            sleep: { _ in events.append("sleep") }
        )
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

@MainActor
private final class FakeWorkspaceClient: WorkspaceClient {
    var application: WorkspaceApplication?
    var activationResult: Bool
    private let events: EventLog

    init(
        application: WorkspaceApplication? = WorkspaceApplication(
            processIdentifier: 1,
            bundleIdentifier: "com.example.App"
        ),
        activationResult: Bool = true,
        events: EventLog = EventLog()
    ) {
        self.application = application
        self.activationResult = activationResult
        self.events = events
    }

    func frontmostApplication() -> WorkspaceApplication? {
        events.append("workspace.frontmost")
        return application
    }

    func activate(processIdentifier: pid_t) -> Bool {
        events.append("workspace.activate:\(processIdentifier)")
        return activationResult
    }
}

@MainActor
private final class FakeAccessibilityClient: AccessibilityClient {
    var isTrusted: Bool
    var focusedElement: AXUIElement?
    var setSelectedTextResult: AXError
    private let events: EventLog
    private(set) var insertedText: String?

    init(
        isTrusted: Bool = true,
        focusedElement: AXUIElement? = nil,
        setSelectedTextResult: AXError = .attributeUnsupported,
        events: EventLog = EventLog()
    ) {
        self.isTrusted = isTrusted
        self.focusedElement = focusedElement
        self.setSelectedTextResult = setSelectedTextResult
        self.events = events
    }

    func copyFocusedElement() -> AXUIElement? {
        events.append("accessibility.focusedElement")
        return focusedElement
    }

    func setSelectedText(_ text: String, in element: AXUIElement) -> AXError {
        events.append("accessibility.setSelectedText")
        insertedText = text
        return setSelectedTextResult
    }
}

@MainActor
private final class FakePasteboardRestorer: PasteboardRestoring {
    private let originalText: String?
    private let events: EventLog
    private(set) var currentText: String?
    private(set) var restoreCount = 0

    init(originalText: String? = nil, events: EventLog = EventLog()) {
        self.originalText = originalText
        self.events = events
    }

    func placeTextPreservingCurrentContents(_ text: String) -> PasteboardSnapshot? {
        events.append("pasteboard.place")
        currentText = text
        return PasteboardSnapshot(items: [])
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        events.append("pasteboard.restore")
        restoreCount += 1
        currentText = originalText
    }
}

@MainActor
private final class FakePasteEventPoster: PasteEventPosting {
    var postResult: Bool
    private let events: EventLog
    private(set) var postCount = 0

    init(postResult: Bool = true, events: EventLog = EventLog()) {
        self.postResult = postResult
        self.events = events
    }

    func postPaste() -> Bool {
        events.append("events.postPaste")
        postCount += 1
        return postResult
    }
}

@MainActor
private final class FakePasteboardClient: PasteboardClient {
    var snapshot: PasteboardSnapshot
    var writeResult: Bool
    private(set) var currentText: String?
    private(set) var restoredSnapshot: PasteboardSnapshot?

    init(snapshot: PasteboardSnapshot, writeResult: Bool = true) {
        self.snapshot = snapshot
        self.writeResult = writeResult
    }

    func captureSnapshot() -> PasteboardSnapshot {
        snapshot
    }

    func writeText(_ text: String) -> Bool {
        currentText = text
        return writeResult
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        restoredSnapshot = snapshot
        currentText = nil
    }
}
