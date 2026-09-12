import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let relaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Whisper Setup", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button("Close Setup") { model.close() }
                    .disabled(model.isTesting || model.requestingPermission)
            }
            if model.step != .ready {
                Text("Step \(model.step.rawValue + 1) of 4")
                    .foregroundStyle(DesignTokens.mutedText)
                ProgressView(value: Double(model.step.rawValue + 1), total: 4)
                    .accessibilityLabel("Setup progress")
            }
            Group {
                switch model.step {
                case .apiKey: apiKey
                case .microphone: permission(.microphone)
                case .screenRecording: permission(.screenRecording)
                case .accessibility:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            permission(.accessibility)
                            Divider()
                            inputMonitoring
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .ready: ready
                }
            }
            Spacer(minLength: 12)
            HStack {
                Button("Back") { model.back() }
                    .disabled(model.step == .apiKey || model.isTesting || model.requestingPermission)
                Spacer()
                if model.step == .ready {
                    Button("Open Home") { model.finish() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") { model.advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isTesting || model.requestingPermission)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 700, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.canvas)
        .task { model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private var apiKey: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect OpenAI").font(.largeTitle.weight(.semibold))
            Text("Your API key is stored in macOS Keychain. Audio is sent to OpenAI for transcription, and transcripts and instructions are sent for text processing. History and recordings are stored on this Mac.")
                .foregroundStyle(DesignTokens.secondaryText)
            SecureField("OpenAI API key", text: $model.keyInput)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isTesting)
            HStack {
                Button("Save and Test") { Task { await model.saveAndTest() } }
                    .disabled(model.isTesting)
                if model.isTesting { ProgressView().controlSize(.small) }
            }
            Text(model.keyStatus).accessibilityIdentifier("key-status")
            Text("Leave the field empty to test your saved key. Continue without a key to explore the app; dictation will require one.")
                .font(.callout).foregroundStyle(DesignTokens.mutedText)
            Link("Create an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
        }
    }

    private func permission(_ kind: PermissionKind) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(kind.setupTitle).font(.largeTitle.weight(.semibold))
            Text(kind.setupExplanation).foregroundStyle(DesignTokens.secondaryText)
            Label(model.permissions[kind].setupLabel,
                  systemImage: model.permissions[kind] == .granted ? "checkmark.circle" : "exclamationmark.circle")
            if model.permissions[kind] != .granted {
                Button("Request Access") { Task { await model.request(kind) } }
                    .disabled(model.requestingPermission)
                Button("Open System Settings") { model.openSettings(for: kind) }
                Text("System Settings → Privacy & Security → \(kind.settingsTitle). Enable Whisper, then return here.")
                    .font(.callout)
            }
            if kind == .screenRecording && model.screenSettingsOpened { relaunchGuidance }

            Button("Check Again") { model.refreshPermissions() }
            Text("You can continue with missing permissions. Only features that need them are affected.")
                .font(.callout).foregroundStyle(DesignTokens.mutedText)
        }
    }

    private var inputMonitoring: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Monitoring").font(.headline)
            Text(PermissionKind.inputMonitoring.setupExplanation)
                .foregroundStyle(DesignTokens.secondaryText)
            Label(model.permissions.inputMonitoring.setupLabel,
                  systemImage: model.permissions.inputMonitoring == .granted ? "checkmark.circle" : "exclamationmark.circle")
                .accessibilityIdentifier("input-monitoring-status")
            if model.permissions.inputMonitoring != .granted {
                HStack {
                    Button("Request Input Monitoring") { Task { await model.request(.inputMonitoring) } }
                        .disabled(model.requestingPermission)
                    Button("Open Input Monitoring Settings") { model.openSettings(for: .inputMonitoring) }
                }
                Text("System Settings → Privacy & Security → Input Monitoring. Enable Whisper, then return here.")
                    .font(.callout)
            }
            if model.inputMonitoringSettingsOpened { relaunchGuidance }
            Button("Check Keyboard Access") { model.refreshPermissions() }
        }
    }

    private var relaunchGuidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("If macOS asks you to quit and reopen Whisper, relaunch to apply the change.")
            Button("Relaunch Whisper", action: relaunch)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isReady ? "Ready" : "Setup needs attention").font(.largeTitle.weight(.semibold))
            Text(model.keyStatus)
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                HStack {
                    Text(kind.settingsTitle)
                    Spacer()
                    Text(model.permissions[kind].setupLabel)
                    if model.permissions[kind] != .granted {
                        Button("Repair \(kind.settingsTitle)") { model.openSettings(for: kind) }
                    }
                }
            }
            if model.screenSettingsOpened || model.inputMonitoringSettingsOpened { relaunchGuidance }
            Divider()
            Text("Right Option")
            Text("Control-Command-M")
            Text("Command-Shift-R")
            Text("Hold to dictate · Switch mode · Record a meeting")
                .foregroundStyle(DesignTokens.mutedText)
            Text("Meeting recording is not available yet. You can open Home with incomplete setup and return from Settings.")
                .font(.callout)
        }
    }
}

extension PermissionKind {
    var settingsTitle: String {
        switch self {
        case .microphone: "Microphone"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }
    var setupTitle: String { "\(settingsTitle) access" }
    var setupExplanation: String {
        switch self {
        case .microphone: "Allow Whisper to hear your voice for dictation and meeting recordings."
        case .screenRecording: "Allow Screen Recording to capture Mac audio during meetings. Dictation works without this permission."
        case .accessibility: "Allow Accessibility to handle Whisper shortcuts and insert text into the active app. Without it, use the menu bar and paste results manually."
        case .inputMonitoring: "Allow Whisper to detect your global shortcuts while you use other apps. Without it, use the menu-bar actions. Keyboard input is not stored or sent to OpenAI."
        }
    }
}

extension PermissionState {
    var setupLabel: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Not Granted"
        case .notDetermined: "Not Requested"
        }
    }
}
