import Observation
import SwiftUI

@MainActor
@Observable
final class RecordingHUDViewModel {
    var elapsedLabel = "00:00:00"
    var microphoneLevel: Float = 0
    var systemAudioLevel: Float = 0
}

struct RecordingHUDView: View {
    let viewModel: RecordingHUDViewModel
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.space16) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DesignTokens.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.space4) {
                Text("Recording Meeting")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.elapsedLabel)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: DesignTokens.space8) {
                hudMeter("Mic", level: viewModel.microphoneLevel)
                hudMeter("Mac", level: viewModel.systemAudioLevel)
            }
            .frame(width: 120)

            Spacer(minLength: DesignTokens.space4)

            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.danger)
                .controlSize(.large)
                .accessibilityLabel("Stop Meeting Recording")
        }
        .padding(.horizontal, DesignTokens.space16)
        .frame(
            width: RecordingHUDController.panelSize.width,
            height: RecordingHUDController.panelSize.height
        )
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                .fill(DesignTokens.surfaceElevated.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func hudMeter(_ label: String, level: Float) -> some View {
        HStack(spacing: DesignTokens.space8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.mutedText)
                .frame(width: 24, alignment: .leading)
            RecordingLevelMeter(level: level, tint: DesignTokens.accent)
                .accessibilityLabel("\(label) audio level")
                .accessibilityValue("\(Int(level * 100)) percent")
        }
    }
}
