import Foundation

enum HotkeyEvent: Equatable, Sendable {
    case keyDown(keyCode: Int, flags: Shortcut.Modifiers, isRepeat: Bool)
    case keyUp(keyCode: Int, flags: Shortcut.Modifiers)
    case flagsChanged(keyCode: Int, flags: Shortcut.Modifiers)
}

enum HotkeyActionEvent: Equatable, Sendable {
    case pressed(ShortcutAction)
    case released(ShortcutAction)
    case invoked(ShortcutAction)
}
