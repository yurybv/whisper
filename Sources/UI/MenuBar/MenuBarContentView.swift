import Observation
import SwiftUI

enum MenuBarCommand: CaseIterable, Equatable, Sendable {
    case startDictation
    case changeMode
    case recordMeeting
    case recentHistory
    case openMainWindow

    var shortcutAction: ShortcutAction? {
        switch self {
        case .startDictation: .pushToTalk
        case .changeMode: .changeMode
        case .recordMeeting: .recordMeeting
        case .recentHistory, .openMainWindow: nil
        }
    }
}

enum MenuBarState: Equatable, Sendable {
    case ready
    case dictating
    case recordingMeeting
    case processing
    case error

    var label: String {
        switch self {
        case .ready: "Whisper ready"
        case .dictating: "Dictation in progress"
        case .recordingMeeting: "Meeting recording in progress"
        case .processing: "Processing dictation"
        case .error: "Whisper needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "waveform"
        case .dictating: "mic.fill"
        case .recordingMeeting: "record.circle.fill"
        case .processing: "ellipsis.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
@Observable
final class MenuBarViewModel {
    var state: MenuBarState
    var currentModeName: String
    var message: String?

    init(
        state: MenuBarState = .ready,
        currentModeName: String = ModeDefinition.defaultMode.name,
        message: String? = nil
    ) {
        self.state = state
        self.currentModeName = currentModeName
        self.message = message
    }
}

struct MenuBarContentView: View {
    let viewModel: MenuBarViewModel
    let onToggleDictation: () -> Void
    let onChangeMode: () -> Void
    let onRecordMeeting: () -> Void
    let onRecentHistory: () -> Void
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space12) {
            HStack(spacing: DesignTokens.space12) {
                Image(systemName: viewModel.state.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.state.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.primaryText)
                    Text("Mode: \(viewModel.currentModeName)")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.secondaryText)
                }
            }

            if let message = viewModel.message {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(DesignTokens.border)

            menuButton(
                viewModel.state == .dictating ? "Finish Dictation" : "Start Dictation",
                systemImage: "mic",
                shortcut: "⌥",
                action: onToggleDictation
            )
            menuButton("Change Mode", systemImage: "square.grid.2x2", shortcut: "⇧⌘K", action: onChangeMode)
            menuButton("Record Meeting", systemImage: "record.circle", shortcut: "⇧⌘R", action: onRecordMeeting)

            Divider().overlay(DesignTokens.border)

            menuButton("Recent History", systemImage: "clock.arrow.circlepath", action: onRecentHistory)
            menuButton("Open Whisper", systemImage: "macwindow", action: onOpenMainWindow)
            menuButton("Quit Whisper", systemImage: "power", action: onQuit)
        }
        .padding(DesignTokens.space16)
        .frame(width: 292)
        .background(DesignTokens.surfaceElevated)
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .ready, .processing: DesignTokens.accent
        case .dictating, .recordingMeeting: DesignTokens.warning
        case .error: DesignTokens.danger
        }
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.space8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.mutedText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 28)
        .foregroundStyle(DesignTokens.primaryText)
    }
}
