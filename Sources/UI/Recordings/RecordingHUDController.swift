import AppKit
import SwiftUI

@MainActor
final class RecordingHUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: RecordingHUDController.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingHUDController {
    static let panelSize = NSSize(width: 440, height: 104)
    private static let screenBottomPadding: CGFloat = 24

    private let panel: RecordingHUDPanel
    private let viewModel = RecordingHUDViewModel()

    init(
        panel: RecordingHUDPanel = RecordingHUDPanel(),
        onStop: @escaping @MainActor () -> Void
    ) {
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: RecordingHUDView(viewModel: viewModel, onStop: onStop)
        )
    }

    func render(model: RecordingsModel, screen: NSScreen? = nil) {
        guard case .recording = model.state else {
            hide()
            return
        }
        viewModel.elapsedLabel = model.elapsedLabel
        viewModel.microphoneLevel = model.microphoneLevel
        viewModel.systemAudioLevel = model.systemAudioLevel
        if let visibleFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrame(Self.frame(panelSize: Self.panelSize, visibleFrame: visibleFrame), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    static func frame(panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + screenBottomPadding,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
