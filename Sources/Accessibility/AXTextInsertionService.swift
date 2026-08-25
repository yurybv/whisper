import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WorkspaceApplication: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

@MainActor
protocol WorkspaceClient: Sendable {
    func frontmostApplication() -> WorkspaceApplication?
    func activate(processIdentifier: pid_t) -> Bool
}

@MainActor
protocol AccessibilityClient: Sendable {
    var isTrusted: Bool { get }
    func copyFocusedElement() -> AXUIElement?
    func setSelectedText(_ text: String, in element: AXUIElement) -> AXError
}

@MainActor
protocol PasteEventPosting: Sendable {
    func postPaste() -> Bool
}

@MainActor
final class AXTextInsertionService: TextInsertionService {
    typealias Sleep = @Sendable (Duration) async -> Void

    private let workspace: any WorkspaceClient
    private let accessibility: any AccessibilityClient
    private let pasteboard: any PasteboardRestoring
    private let eventPoster: any PasteEventPosting
    private let sleep: Sleep

    init(
        workspace: any WorkspaceClient = SystemWorkspaceClient(),
        accessibility: any AccessibilityClient = SystemAccessibilityClient(),
        pasteboard: any PasteboardRestoring = PasteboardRestorer(),
        eventPoster: any PasteEventPosting = CGPasteEventPoster(),
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.workspace = workspace
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.sleep = sleep
    }

    func captureFocusedTarget() async throws -> FocusedTarget {
        guard let application = workspace.frontmostApplication() else {
            throw TextInsertionError.noFocusedApplication
        }
        return FocusedTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            element: accessibility.copyFocusedElement()
        )
    }

    func insert(_ text: String, into target: FocusedTarget) async throws -> InsertionResult {
        if accessibility.isTrusted,
           let element = target.element,
           accessibility.setSelectedText(text, in: element) == .success {
            return .insertedDirectly
        }

        let activated = accessibility.isTrusted
            ? workspace.activate(processIdentifier: target.processIdentifier)
            : false
        guard let snapshot = pasteboard.placeTextPreservingCurrentContents(text) else {
            throw TextInsertionError.clipboardWriteFailed
        }
        guard activated, eventPoster.postPaste() else {
            return .copiedForManualPaste
        }

        await sleep(.milliseconds(150))
        pasteboard.restore(snapshot)
        return .pasted
    }
}

@MainActor
final class SystemWorkspaceClient: WorkspaceClient {
    func frontmostApplication() -> WorkspaceApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return WorkspaceApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    func activate(processIdentifier: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: processIdentifier)?
            .activate(options: [.activateAllWindows]) ?? false
    }
}

@MainActor
final class SystemAccessibilityClient: AccessibilityClient {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func copyFocusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    func setSelectedText(_ text: String, in element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
    }
}

@MainActor
final class CGPasteEventPoster: PasteEventPosting {
    private static let vKeyCode: CGKeyCode = 9

    func postPaste() -> Bool {
        guard
            let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.vKeyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.vKeyCode,
                keyDown: false
            )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
