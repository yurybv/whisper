import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel
    let previewSetup: () -> Void
    let resetSetup: () -> Void
    @State private var confirmsKeyRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                ScreenHeader(
                    title: "Settings",
                    subtitle: "Configure services, audio, shortcuts, and local behavior."
                )

                SettingsCard("OpenAI API Key", subtitle: "Stored only in macOS Keychain") {
                    HStack(spacing: DesignTokens.space12) {
                        if model.apiKeyState == .missing || model.isReplacingAPIKey {
                            SecureField("OpenAI API key", text: $model.apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text("••••••••••••")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText)
                                .accessibilityIdentifier("••••••••••••")
                                .accessibilityLabel("Saved API key")
                        }
                        Spacer()
                        if model.apiKeyState == .missing || model.isReplacingAPIKey {
                            Button("Save") { model.saveAPIKeyForPresentation() }
                                .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if model.isReplacingAPIKey {
                                Button("Cancel") { model.cancelAPIKeyReplacement() }
                            }
                        } else {
                            Button("Replace") { model.beginAPIKeyReplacement() }
                                .disabled(model.apiKeyState == .testing)
                            Button("Remove", role: .destructive) { confirmsKeyRemoval = true }
                                .disabled(model.apiKeyState == .testing)
                        }
                        Button("Test Connection") { Task { await model.testAPIConnection() } }
                            .disabled(
                                model.apiKeyState == .missing
                                    || model.apiKeyState == .testing
                                    || model.isReplacingAPIKey
                            )
                    }
                    Label(model.apiKeyStatusLabel, systemImage: apiStatusImage)
                        .font(.system(size: 12))
                        .foregroundStyle(apiStatusColor)
                    if let errorMessage = model.apiKeyErrorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.warning)
                            .accessibilityLabel("OpenAI API key error: \(errorMessage)")
                    }
                }

                SettingsCard("Audio Input", subtitle: "Used for dictation and your side of recordings") {
                    HStack {
                        Text("Microphone")
                        Spacer()
                        Picker("Microphone", selection: microphoneSelection) {
                            Text("System Default").tag("")
                            ForEach(model.microphones) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 300)
                        .accessibilityLabel("Microphone")
                        .accessibilityIdentifier("Microphone")
                    }
                    .frame(minHeight: 44)
                    Text("Input level appears in the dictation HUD while recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.mutedText)
                }

                SettingsCard("Keyboard Shortcuts", subtitle: "Click Record, then press a new shortcut") {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        ShortcutRecorderView(
                            action: action,
                            shortcut: model.shortcuts[action] ?? AppSettings.defaults.shortcuts[action]!,
                            isCapturing: model.capturingShortcut == action,
                            onRecord: { model.beginShortcutCapture(action) },
                            onReset: { model.resetShortcut(action) }
                        )
                        if action != ShortcutAction.allCases.last { Divider().overlay(DesignTokens.border) }
                    }
                    if let shortcutError = model.shortcutError {
                        Label(shortcutError, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.warning)
                    }
                }

                SettingsCard("Application") {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                    if model.launchAtLoginState == .requiresApproval {
                        HStack {
                            Text("Approval is required in Login Items.")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.warning)
                            Spacer()
                            Button("Open Login Items") { model.openLoginItemsSettings() }
                        }
                    }
                    if let errorMessage = model.launchAtLoginErrorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.warning)
                            .accessibilityLabel("Launch at Login error: \(errorMessage)")
                    }
                    Divider().overlay(DesignTokens.border)
                    Toggle("Sound Effects", isOn: soundBinding)
                        .toggleStyle(.switch)
                    Divider().overlay(DesignTokens.border)
                    HStack {
                        Text("Keep Recordings")
                        Spacer()
                        Text("Forever")
                            .foregroundStyle(DesignTokens.secondaryText)
                    }
                    .frame(minHeight: 36)
                }

                SettingsCard("Permissions", subtitle: "Open the exact Privacy & Security pane to repair access") {
                    ForEach(PermissionKind.allCases, id: \.self) { kind in
                        PermissionRow(
                            kind: kind,
                            state: model.permissions[kind],
                            showRepair: true,
                            repair: { model.openPermissionSettings(kind) }
                        )
                        if kind != PermissionKind.allCases.last { Divider().overlay(DesignTokens.border) }
                    }
                }

                SettingsCard("Setup") {
                    HStack {
                        Text("Review the first-run guide or reset setup progress.")
                            .foregroundStyle(DesignTokens.secondaryText)
                        Spacer()
                        Button("Preview Setup", action: previewSetup)
                        Button("Reset Setup", action: resetSetup)
                    }
                }

                SettingsCard("About") {
                    HStack {
                        Label("Whisper", systemImage: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Version 1.0 · Personal local build")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.mutedText)
                    }
                }

            }
            .padding(DesignTokens.space32)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(DesignTokens.canvas)
        .onAppear { model.refresh() }
        .alert("Remove OpenAI API key?", isPresented: $confirmsKeyRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.removeAPIKeyForPresentation() }
        } message: {
            Text("Dictation and recording processing will remain unavailable until another key is saved.")
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding(
            get: { model.selectedMicrophoneID ?? "" },
            set: { model.selectMicrophone($0.isEmpty ? nil : $0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginState == .enabled },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { model.soundEffects }, set: { model.setSoundEffects($0) })
    }

    private var apiStatusImage: String {
        switch model.apiKeyState {
        case .connected: "checkmark.circle.fill"
        case .testing: "ellipsis.circle"
        case .failed: "exclamationmark.triangle"
        case .missing, .saved: "key"
        }
    }

    private var apiStatusColor: Color {
        switch model.apiKeyState {
        case .connected: DesignTokens.success
        case .failed: DesignTokens.warning
        case .missing, .saved, .testing: DesignTokens.secondaryText
        }
    }
}
