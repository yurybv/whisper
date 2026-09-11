import AppKit
import CoreGraphics
import Observation
import SwiftUI

@MainActor
protocol ModeSwitcherPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    func present()
    func dismiss()
}

@MainActor
protocol ApplicationRestoring: AnyObject {
    @discardableResult
    func restoreActivation() -> Bool
}

extension NSRunningApplication: ApplicationRestoring {
    @discardableResult
    func restoreActivation() -> Bool {
        activate(options: [.activateAllWindows])
    }
}

@MainActor
final class ModeSwitcherPanel: NSPanel, ModeSwitcherPanelPresenting {
    private static let contentSize = NSSize(width: 560, height: 420)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        contentView?.layoutSubtreeIfNeeded()
        let visibleFrame = (Self.builtInScreen() ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        if let visibleFrame { place(in: visibleFrame) }
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        makeKeyAndOrderFront(nil)
        contentView?.layoutSubtreeIfNeeded()
        if let visibleFrame {
            setFrame(Self.frame(panelSize: frame.size, visibleFrame: visibleFrame), display: true)
        }
        orderFrontRegardless()
        if let visibleFrame {
            DispatchQueue.main.async { [weak self] in
                guard let self, isVisible else { return }
                contentView?.layoutSubtreeIfNeeded()
                setFrame(Self.frame(panelSize: frame.size, visibleFrame: visibleFrame), display: true)
                orderFrontRegardless()
            }
        }
    }

    func dismiss() {
        orderOut(nil)
    }

    func place(in visibleFrame: NSRect) {
        setContentSize(Self.contentSize)
        setFrame(Self.frame(panelSize: frame.size, visibleFrame: visibleFrame), display: true)
    }

    static func frame(panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        }
    }
}

@MainActor
final class ModeSwitcherPanelLifecycle {
    typealias FrontmostApplication = () -> (any ApplicationRestoring)?

    private let panel: any ModeSwitcherPanelPresenting
    private let frontmostApplication: FrontmostApplication
    private var previousApplication: (any ApplicationRestoring)?

    init(
        panel: any ModeSwitcherPanelPresenting,
        frontmostApplication: @escaping FrontmostApplication
    ) {
        self.panel = panel
        self.frontmostApplication = frontmostApplication
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        if !panel.isVisible {
            previousApplication = frontmostApplication()
        }
        panel.present()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.dismiss()
        let application = previousApplication
        previousApplication = nil
        _ = application?.restoreActivation()
    }
}

@MainActor
@Observable
final class ModeSwitcherViewModel {
    private(set) var model: ModeSwitcherModel
    private let onActivate: (UUID) -> Void
    private let onClose: () -> Void

    init(
        model: ModeSwitcherModel,
        onActivate: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.onActivate = onActivate
        self.onClose = onClose
    }

    var query: String {
        get { model.query }
        set { model.query = newValue }
    }

    var modes: [ModeDefinition] { model.filteredModes }
    var activeModeID: UUID { model.activeModeID }
    var selectedModeID: UUID? { model.selectedModeID }

    func select(_ id: UUID) {
        model.select(id)
    }

    func move(_ direction: ModeSwitcherModel.SelectionDirection) {
        model.moveSelection(direction)
    }

    func activateSelection() {
        guard case let .activate(id) = model.handle(.activate) else { return }
        onActivate(id)
    }

    func close() {
        onClose()
    }
}

@MainActor
final class ModeSwitcherController {
    typealias ModesProvider = () throws -> (modes: [ModeDefinition], activeModeID: UUID)
    typealias ModeActivator = (UUID) throws -> Void

    private let panel: ModeSwitcherPanel
    private let lifecycle: ModeSwitcherPanelLifecycle
    private let modesProvider: ModesProvider
    private let activateMode: ModeActivator
    private let onModeActivated: (ModeDefinition) -> Void
    private let onClosed: () -> Void
    private var viewModel: ModeSwitcherViewModel?

    init(
        panel: ModeSwitcherPanel,
        modesProvider: @escaping ModesProvider,
        activateMode: @escaping ModeActivator,
        onModeActivated: @escaping (ModeDefinition) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.panel = panel
        lifecycle = ModeSwitcherPanelLifecycle(
            panel: panel,
            frontmostApplication: {
                guard
                    let application = NSWorkspace.shared.frontmostApplication,
                    application.processIdentifier != NSRunningApplication.current.processIdentifier
                else {
                    return nil
                }
                return application
            }
        )
        self.modesProvider = modesProvider
        self.activateMode = activateMode
        self.onModeActivated = onModeActivated
        self.onClosed = onClosed
    }

    var isVisible: Bool { lifecycle.isVisible }

    func show() throws {
        let snapshot = try modesProvider()
        let modesByID = Dictionary(uniqueKeysWithValues: snapshot.modes.map { ($0.id, $0) })
        let viewModel = ModeSwitcherViewModel(
            model: ModeSwitcherModel(
                modes: snapshot.modes,
                activeModeID: snapshot.activeModeID
            ),
            onActivate: { [weak self] id in
                guard let self else { return }
                do {
                    try self.activateMode(id)
                    if let mode = modesByID[id] {
                        self.onModeActivated(mode)
                    }
                    self.close()
                } catch {
                    NSSound.beep()
                }
            },
            onClose: { [weak self] in self?.close() }
        )
        self.viewModel = viewModel
        panel.contentViewController = NSHostingController(
            rootView: ModeSwitcherView(viewModel: viewModel)
        )
        lifecycle.show()
    }

    func close() {
        let wasVisible = lifecycle.isVisible
        lifecycle.close()
        viewModel = nil
        if wasVisible {
            onClosed()
        }
    }
}
