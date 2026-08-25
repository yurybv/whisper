import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        _ = NSRunningApplication.current.activate(options: [])
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whisper"
        window.minSize = NSSize(width: 720, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: Color(DesignTokens.canvas)
                .frame(
                    minWidth: DesignTokens.sidebarWidth,
                    idealWidth: DesignTokens.contentMaxWidth,
                    minHeight: 560
                )
                .preferredColorScheme(.dark)
        )
        return window
    }
}
