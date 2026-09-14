import SwiftUI

struct RecordingsView: View {
    @Bindable var model: RecordingsModel

    private let columns = [
        GridItem(.flexible(), spacing: DesignTokens.space16),
        GridItem(.flexible(), spacing: DesignTokens.space16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                ScreenHeader(
                    title: "Recordings",
                    subtitle: "Capture your microphone and Mac audio into durable local tracks."
                )

                recordingStatus

                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.space16) {
                    sourceCard(
                        title: "System Audio",
                        detail: "Mac application and call audio",
                        systemImage: "desktopcomputer",
                        permission: model.screenRecordingPermission,
                        permissionKind: .screenRecording,
                        level: model.systemAudioLevel
                    )
                    microphoneCard
                }

                SettingsCard("Recording Controls", subtitle: "Available globally while Whisper is running") {
                    HStack(spacing: DesignTokens.space24) {
                        metadata("Meeting shortcut", value: model.recordingShortcut, keycap: true)
                        metadata("Maximum duration", value: "3 hours", keycap: false)
                        Spacer()
                    }
                }

                SettingsCard("Processing Instructions", subtitle: "Saved at Start and kept stable for this recording") {
                    TextEditor(text: $model.instructions)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.space8)
                        .frame(minHeight: 170)
                        .background(DesignTokens.surfaceCard)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.controlRadius)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                        .disabled(!model.canEditConfiguration)
                        .accessibilityLabel("Processing Instructions")

                    HStack(spacing: DesignTokens.space16) {
                        Text("Result Language")
                            .font(.system(size: 13, weight: .medium))
                        Picker("Result Language", selection: $model.resultLanguage) {
                            ForEach(RecordingResultLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        .disabled(!model.canEditConfiguration)
                        Spacer()
                    }
                }

                Label(
                    "Source audio stays in Whisper's local Application Support folder. Only temporary audio chunks are sent to OpenAI for transcription.",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.space32)
            .frame(maxWidth: DesignTokens.contentMaxWidth, alignment: .leading)
        }
        .background(DesignTokens.canvas)
        .onAppear { model.refresh() }
    }

    private var recordingStatus: some View {
        SettingsCard(model.statusTitle, subtitle: model.statusMessage) {
            HStack(spacing: DesignTokens.space24) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Image(systemName: statusImage)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.space8) {
                    Text(model.elapsedLabel)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .accessibilityLabel("Elapsed time")
                        .accessibilityValue(model.elapsedLabel)
                    if case .recording = model.state {
                        HStack(spacing: DesignTokens.space16) {
                            compactMeter("Microphone", level: model.microphoneLevel)
                            compactMeter("System", level: model.systemAudioLevel)
                        }
                    }
                }

                Spacer()

                if case .recording = model.state {
                    Button("Cancel") {
                        Task { await model.cancelRecording() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("Cancel Recording")
                }
                Button(model.primaryButtonTitle) {
                    Task { await model.toggleRecording() }
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryTint)
                .controlSize(.large)
                .disabled(!model.canToggleRecording)
                .accessibilityIdentifier(model.primaryButtonTitle)
            }
            .frame(minHeight: 76)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var microphoneCard: some View {
        SettingsCard("Microphone", subtitle: "Your side of the conversation") {
            sourceStatus(permission: model.microphonePermission, label: "Microphone")
            Picker("Microphone", selection: Binding(
                get: { model.selectedMicrophoneID },
                set: { model.selectMicrophone($0) }
            )) {
                Text("System Default").tag(String?.none)
                ForEach(model.microphones) { microphone in
                    Text(microphone.name).tag(Optional(microphone.id))
                }
            }
            .disabled(!model.canEditConfiguration)
            if case .recording = model.state {
                RecordingLevelMeter(level: model.microphoneLevel, tint: DesignTokens.accent)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(model.microphoneLevel * 100)) percent")
            }
            permissionRecovery(.microphone, state: model.microphonePermission)
        }
    }

    private func sourceCard(
        title: String,
        detail: String,
        systemImage: String,
        permission: PermissionState,
        permissionKind: PermissionKind,
        level: Float
    ) -> some View {
        SettingsCard(title, subtitle: detail) {
            HStack(spacing: DesignTokens.space8) {
                Image(systemName: systemImage)
                    .foregroundStyle(DesignTokens.accent)
                    .accessibilityHidden(true)
                sourceStatus(permission: permission, label: title)
            }
            if case .recording = model.state {
                RecordingLevelMeter(level: level, tint: DesignTokens.success)
                    .accessibilityLabel("\(title) level")
                    .accessibilityValue("\(Int(level * 100)) percent")
            }
            permissionRecovery(permissionKind, state: permission)
        }
    }

    private func sourceStatus(permission: PermissionState, label: String) -> some View {
        Label(
            permission == .granted ? "Enabled" : "Permission required",
            systemImage: permission == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(permission == .granted ? DesignTokens.success : DesignTokens.warning)
        .accessibilityLabel("\(label) status")
        .accessibilityValue(permission == .granted ? "Enabled" : "Permission required")
    }

    @ViewBuilder
    private func permissionRecovery(_ kind: PermissionKind, state: PermissionState) -> some View {
        if state != .granted {
            Button("Open System Settings") { model.openPermissionSettings(kind) }
                .buttonStyle(.link)
                .accessibilityLabel("Open \(kind.rawValue) permission settings")
        }
    }

    private func metadata(_ label: String, value: String, keycap: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.space8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.mutedText)
            if keycap {
                KeycapView(text: value)
            } else {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private func compactMeter(_ label: String, level: Float) -> some View {
        HStack(spacing: DesignTokens.space8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.mutedText)
            RecordingLevelMeter(level: level, tint: DesignTokens.accent)
                .frame(width: 90)
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .recording: DesignTokens.danger
        case .failed: DesignTokens.warning
        case .ready: DesignTokens.success
        default: DesignTokens.accent
        }
    }

    private var statusImage: String {
        switch model.state {
        case .recording: "record.circle.fill"
        case .finalizing: "stop.circle"
        case .captured: "externaldrive.fill.badge.checkmark"
        case .transcribing: "waveform.badge.magnifyingglass"
        case .processing: "sparkles"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "record.circle"
        }
    }

    private var primaryTint: Color {
        if case .recording = model.state { return DesignTokens.danger }
        return DesignTokens.accent
    }
}

struct RecordingLevelMeter: View {
    let level: Float
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DesignTokens.border)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}
