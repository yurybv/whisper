import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: MenuBarViewModel

    init(
        viewModel: MenuBarViewModel = MenuBarViewModel(),
        onToggleDictation: @escaping () -> Void,
        onChangeMode: @escaping () -> Void,
        onRecordMeeting: @escaping () -> Void,
        onRetryDictation: @escaping () -> Void,
        onDiscardDictation: @escaping () -> Void,
        onRecentHistory: @escaping () -> Void,
        onOpenMainWindow: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                viewModel: viewModel,
                onToggleDictation: onToggleDictation,
                onChangeMode: onChangeMode,
                onRecordMeeting: onRecordMeeting,
                onRetryDictation: onRetryDictation,
                onDiscardDictation: onDiscardDictation,
                onRecentHistory: onRecentHistory,
                onOpenMainWindow: onOpenMainWindow,
                onQuit: onQuit
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateStatusItem()
    }

    func render(
        state: MenuBarState,
        modeName: String? = nil,
        message: String? = nil,
        dictationRecovery: DictationRecovery? = nil
    ) {
        viewModel.state = state
        if let modeName {
            viewModel.currentModeName = modeName
        }
        viewModel.message = message
        if let dictationRecovery {
            viewModel.dictationRecovery = dictationRecovery
        }
        updateStatusItem()
    }

    func setModeName(_ name: String) {
        viewModel.currentModeName = name
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: viewModel.state.systemImage, accessibilityDescription: viewModel.state.label)
        image?.isTemplate = viewModel.state != .error
        button.image = image
        button.toolTip = viewModel.state.label
        button.setAccessibilityLabel(viewModel.state.label)
    }
}
