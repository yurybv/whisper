import SwiftUI

struct ShortcutRecorderView: View {
    let action: ShortcutAction
    let shortcut: Shortcut
    let isCapturing: Bool
    let onRecord: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .foregroundStyle(DesignTokens.primaryText)
                Text(action.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.mutedText)
            }
            Spacer()
            KeycapView(text: isCapturing ? "Press shortcut…" : shortcut.displayName)
            Button(isCapturing ? "Listening" : "Record") {
                onRecord()
            }
            .disabled(isCapturing)
            .accessibilityLabel("Record \(action.title) shortcut")
            Button("Reset", action: onReset)
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset \(action.title) shortcut")
        }
        .frame(minHeight: 48)
    }
}

extension ShortcutAction {
    var explanation: String {
        switch self {
        case .pushToTalk: "Hold while speaking"
        case .changeMode: "Open the mode switcher"
        case .recordMeeting: "Start or stop recording"
        case .cancel: "Cancel the active action"
        }
    }
}

extension Shortcut {
    var displayName: String {
        if key == .rightOption { return "Right Option" }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        parts.append(key.displayName)
        return parts.joined(separator: "-")
    }
}

private extension Shortcut.Key {
    var displayName: String {
        switch self {
        case .escape: "Escape"
        case .k: "K"
        case .m: "M"
        case .r: "R"
        default: "Key \(keyCode)"
        }
    }
}
