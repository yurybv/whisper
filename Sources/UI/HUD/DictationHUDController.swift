import AppKit
import Observation
import SwiftUI

enum DictationHUDStatus: Equatable, Sendable {
    case listening(modeName: String)
    case transcribing
    case processing
    case inserting
    case inserted
    case cancelled
    case error(message: String, textOnClipboard: Bool)
}

struct DictationHUDPresentation: Equatable, Sendable {
    enum Accent: Equatable, Sendable {
        case accent
        case success
        case warning
        case danger
    }

    let title: String
    let detail: String
    let systemImage: String
    let accent: Accent

    init(state: DictationState) {
        switch state {
        case let .recording(modeName):
            self.init(status: .listening(modeName: modeName))
        case .transcribing:
            self.init(status: .transcribing)
        case .transforming:
            self.init(status: .processing)
        case .inserting:
            self.init(status: .inserting)
        case .completed:
            self.init(status: .inserted)
        case let .failed(message, textOnClipboard):
            self.init(status: .error(message: message, textOnClipboard: textOnClipboard))
        case .idle:
            self.init(
                title: "Ready",
                detail: "Hold Right Option to dictate",
                systemImage: "waveform",
                accent: .accent
            )
        }
    }

    init(status: DictationHUDStatus) {
        switch status {
        case let .listening(modeName):
            self.init(
                title: "Listening",
                detail: modeName,
                systemImage: "waveform",
                accent: .accent
            )
        case .transcribing:
            self.init(
                title: "Transcribing",
                detail: "Turning speech into text",
                systemImage: "text.bubble",
                accent: .accent
            )
        case .processing:
            self.init(
                title: "Processing",
                detail: "Applying mode instructions",
                systemImage: "sparkles",
                accent: .accent
            )
        case .inserting:
            self.init(
                title: "Inserting",
                detail: "Restoring the target application",
                systemImage: "arrow.down.doc",
                accent: .accent
            )
        case .inserted:
            self.init(
                title: "Inserted",
                detail: "Dictation is ready",
                systemImage: "checkmark.circle.fill",
                accent: .success
            )
        case .cancelled:
            self.init(
                title: "Cancelled",
                detail: "Nothing was inserted",
                systemImage: "xmark.circle",
                accent: .warning
            )
        case let .error(message, textOnClipboard):
            self.init(
                title: "Dictation failed",
                detail: textOnClipboard ? "Text is on the clipboard" : message,
                systemImage: "exclamationmark.triangle.fill",
                accent: .danger
            )
        }
    }

    private init(title: String, detail: String, systemImage: String, accent: Accent) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.accent = accent
    }
}

@MainActor
@Observable
final class DictationHUDViewModel {
    var presentation = DictationHUDPresentation(state: .idle)
    var level: Float = 0
}

@MainActor
final class DictationHUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: DictationHUDController.panelSize),
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
final class DictationHUDController {
    static let panelSize = NSSize(width: 360, height: 92)
    private static let screenBottomPadding: CGFloat = 24

    private let panel: DictationHUDPanel
    private let viewModel: DictationHUDViewModel
    private var dismissalTask: Task<Void, Never>?

    init(panel: DictationHUDPanel = DictationHUDPanel()) {
        self.panel = panel
        viewModel = DictationHUDViewModel()
        panel.contentViewController = NSHostingController(
            rootView: DictationHUDView(viewModel: viewModel)
        )
    }

    func render(state: DictationState, level: Float = 0, screen: NSScreen? = nil) {
        guard state != .idle else {
            hide()
            return
        }
        render(
            presentation: DictationHUDPresentation(state: state),
            level: level,
            screen: screen,
            dismissAfter: state == .completed ? .seconds(1.2) : nil
        )
    }

    func render(status: DictationHUDStatus, level: Float = 0, screen: NSScreen? = nil) {
        render(
            presentation: DictationHUDPresentation(status: status),
            level: level,
            screen: screen,
            dismissAfter: status == .cancelled ? .seconds(1.2) : nil
        )
    }

    func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel.orderOut(nil)
    }

    static func frame(panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + screenBottomPadding,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func render(
        presentation: DictationHUDPresentation,
        level: Float,
        screen: NSScreen?,
        dismissAfter: Duration?
    ) {
        dismissalTask?.cancel()
        viewModel.presentation = presentation
        viewModel.level = min(max(level, 0), 1)

        if let visibleFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrame(Self.frame(panelSize: Self.panelSize, visibleFrame: visibleFrame), display: true)
        }
        panel.orderFrontRegardless()

        guard let dismissAfter else { return }
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: dismissAfter)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}
