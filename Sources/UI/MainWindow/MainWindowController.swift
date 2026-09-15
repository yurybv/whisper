import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    typealias RootViewBuilder = (@escaping () -> Void) -> AnyView

    private var window: NSWindow?
    private let rootViewBuilder: RootViewBuilder
    private let preferredScreen: (() -> NSScreen?)?

    init(
        preferredScreen: (() -> NSScreen?)? = nil,
        rootViewBuilder: @escaping RootViewBuilder
    ) {
        self.preferredScreen = preferredScreen
        self.rootViewBuilder = rootViewBuilder
        super.init()
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

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
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whisper"
        window.minSize = NSSize(width: 1120, height: 760)
        window.isReleasedWhenClosed = false
        if let visibleFrame = preferredScreen?()?.visibleFrame {
            window.setFrame(
                NSRect(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2,
                    width: window.frame.width,
                    height: window.frame.height
                ),
                display: false
            )
        } else {
            window.center()
        }
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: rootViewBuilder { [weak self] in self?.relaunch() }
        )
        return window
    }
}
