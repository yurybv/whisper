import SwiftUI

struct HomeView: View {
    @Bindable var home: HomeModel
    @Bindable var modes: ModesModel
    @Bindable var settings: SettingsModel
    let startDictation: () -> Void
    let changeMode: () -> Void
    let recordMeeting: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: DesignTokens.space16, alignment: .top),
        GridItem(.flexible(), spacing: DesignTokens.space16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                ScreenHeader(
                    title: readinessTitle,
                    subtitle: HomeReadiness.subtitle(
                        permissions: settings.permissions,
                        apiKey: settings.apiKeyState
                    )
                )

                HStack(spacing: DesignTokens.space12) {
                    Button(action: startDictation) {
                        Label("Start Dictation", systemImage: "mic.fill")
                            .frame(minWidth: 128)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: changeMode) {
                        Label("Change Mode", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.bordered)
                    Button(action: recordMeeting) {
                        Label("Record Meeting", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .controlSize(.large)

                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.space16) {
                    SettingsCard("Active Mode", subtitle: "Applied to your next dictation") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignTokens.success)
                            Text(activeMode.name)
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            KeycapView(text: shortcut(.changeMode))
                        }
                    }

                    SettingsCard("Audio Input", subtitle: "Microphone used for dictation") {
                        Label(settings.selectedMicrophoneName, systemImage: "mic")
                            .foregroundStyle(DesignTokens.primaryText)
                            .frame(minHeight: 32)
                    }

                    SettingsCard("OpenAI", subtitle: "Transcription and text processing") {
                        statusRow(
                            title: settings.apiKeyStatusLabel,
                            isReady: settings.apiKeyState == .connected || settings.apiKeyState == .saved
                        )
                    }

                    SettingsCard("Permissions", subtitle: "Only dependent features are affected") {
                        ForEach(PermissionKind.allCases, id: \.self) { kind in
                            PermissionRow(kind: kind, state: settings.permissions[kind])
                            if kind != PermissionKind.allCases.last { Divider().overlay(DesignTokens.border) }
                        }
                    }
                }

                SettingsCard("Shortcuts", subtitle: "Available globally while Whisper is running") {
                    HStack(spacing: DesignTokens.space16) {
                        shortcutSummary(.pushToTalk)
                        shortcutSummary(.changeMode)
                        shortcutSummary(.recordMeeting)
                    }
                }

                SettingsCard("Recent History", subtitle: "Your five latest local items") {
                    if let errorMessage = home.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DesignTokens.warning)
                    } else if home.recentHistory.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.space8) {
                            Text("No history yet")
                                .font(.system(size: 15, weight: .medium))
                            Text("Completed dictations and recordings will appear here.")
                                .font(.system(size: 13))
                                .foregroundStyle(DesignTokens.mutedText)
                        }
                        .frame(minHeight: 56)
                    } else {
                        ForEach(home.recentHistory) { item in
                            recentRow(item)
                            if item.id != home.recentHistory.last?.id { Divider().overlay(DesignTokens.border) }
                        }
                    }
                }
            }
            .padding(DesignTokens.space32)
            .frame(maxWidth: DesignTokens.contentMaxWidth, alignment: .leading)
        }
        .background(DesignTokens.canvas)
        .onAppear {
            modes.reloadForPresentation()
            settings.refresh()
            home.refresh()
        }
    }

    private var activeMode: ModeDefinition {
        modes.modes.first(where: { $0.id == modes.activeModeID }) ?? .defaultMode
    }

    private var readinessTitle: String {
        HomeReadiness.title(
            microphone: settings.permissions.microphone,
            apiKey: settings.apiKeyState
        )
    }

    private func shortcut(_ action: ShortcutAction) -> String {
        settings.shortcuts[action]?.displayName ?? "Not set"
    }

    private func shortcutSummary(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.space8) {
            Text(action.title)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.mutedText)
            KeycapView(text: shortcut(action))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(title: String, isReady: Bool) -> some View {
        HStack(spacing: DesignTokens.space8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isReady ? DesignTokens.success : DesignTokens.warning)
            Text(title)
                .foregroundStyle(DesignTokens.primaryText)
        }
        .frame(minHeight: 32)
    }

    private func recentRow(_ item: RecentHistoryItem) -> some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: item.kind == .dictation ? "text.bubble" : "waveform")
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                    Text(item.status)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.mutedText)
                }
                Text(item.preview.isEmpty ? "No preview" : item.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.date, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.mutedText)
        }
        .frame(minHeight: 52)
    }
}
