import Foundation

struct HotkeyStateMachine: Sendable {
    private(set) var shortcuts: [ShortcutAction: Shortcut]
    private var activeActions: Set<ShortcutAction> = []
    private var isFeatureActive = false
    private var isMeetingActive = false

    init(shortcuts: [ShortcutAction: Shortcut]) {
        self.shortcuts = shortcuts
    }

    mutating func consume(_ event: HotkeyEvent) -> HotkeyActionEvent? {
        switch event {
        case let .keyDown(keyCode, flags, isRepeat):
            guard !isRepeat,
                  let action = matchingAction(keyCode: keyCode, flags: flags),
                  isAllowed(action) else {
                return nil
            }
            if action == .pushToTalk {
                guard activeActions.insert(action).inserted else {
                    return nil
                }
                return .pressed(action)
            }
            return .invoked(action)

        case let .keyUp(keyCode, _):
            guard shortcuts[.pushToTalk]?.key.keyCode == keyCode,
                  activeActions.remove(.pushToTalk) != nil else {
                return nil
            }
            return .released(.pushToTalk)

        case let .flagsChanged(keyCode, flags):
            guard let (action, shortcut) = modifierAction(keyCode: keyCode) else {
                return nil
            }
            if activeActions.contains(action) {
                guard !flags.contains(shortcut.modifiers) else {
                    return nil
                }
                activeActions.remove(action)
                return action == .pushToTalk ? .released(action) : nil
            }
            guard flags == shortcut.modifiers, isAllowed(action) else {
                return nil
            }
            activeActions.insert(action)
            return action == .pushToTalk ? .pressed(action) : .invoked(action)
        }
    }

    mutating func setFeatureActive(_ isActive: Bool) {
        isFeatureActive = isActive
    }

    mutating func setMeetingActive(_ isActive: Bool) {
        isMeetingActive = isActive
    }

    mutating func updateShortcuts(_ shortcuts: [ShortcutAction: Shortcut]) {
        self.shortcuts = shortcuts
        activeActions.removeAll()
    }

    mutating func resetToDefaults() {
        updateShortcuts(AppSettings.defaults.shortcuts)
    }

    private func matchingAction(
        keyCode: Int,
        flags: Shortcut.Modifiers
    ) -> ShortcutAction? {
        ShortcutAction.allCases.first { action in
            guard let shortcut = shortcuts[action],
                  !Self.modifierKeyCodes.contains(shortcut.key.keyCode) else {
                return false
            }
            return shortcut.key.keyCode == keyCode && shortcut.modifiers == flags
        }
    }

    private func modifierAction(keyCode: Int) -> (ShortcutAction, Shortcut)? {
        ShortcutAction.allCases.lazy.compactMap { action -> (ShortcutAction, Shortcut)? in
            guard let shortcut = shortcuts[action],
                  Self.modifierKeyCodes.contains(shortcut.key.keyCode),
                  shortcut.key.keyCode == keyCode else {
                return nil
            }
            return (action, shortcut)
        }.first
    }

    private func isAllowed(_ action: ShortcutAction) -> Bool {
        switch action {
        case .pushToTalk:
            !isMeetingActive
        case .cancel:
            isFeatureActive
        case .changeMode, .recordMeeting:
            true
        }
    }

    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
}

struct ShortcutCaptureStateMachine: Sendable {
    private(set) var isCapturing = false
    private var pendingModifier: Shortcut?

    mutating func beginCapture() {
        isCapturing = true
        pendingModifier = nil
    }

    mutating func cancelCapture() {
        isCapturing = false
        pendingModifier = nil
    }

    mutating func consume(_ event: HotkeyEvent) -> Shortcut? {
        guard isCapturing else {
            return nil
        }

        let shortcut: Shortcut?
        switch event {
        case let .flagsChanged(keyCode, flags):
            guard let modifier = Self.modifier(for: keyCode) else {
                return nil
            }
            if flags.contains(modifier) {
                pendingModifier = Shortcut(key: Shortcut.Key(keyCode), modifiers: flags)
                return nil
            }
            shortcut = pendingModifier
        case let .keyDown(keyCode, flags, isRepeat):
            guard !isRepeat else {
                return nil
            }
            pendingModifier = nil
            shortcut = Shortcut(key: Shortcut.Key(keyCode), modifiers: flags)
        case .keyUp:
            return nil
        }

        if shortcut != nil {
            isCapturing = false
            pendingModifier = nil
        }
        return shortcut
    }

    private static func modifier(for keyCode: Int) -> Shortcut.Modifiers? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        default: nil
        }
    }
}
