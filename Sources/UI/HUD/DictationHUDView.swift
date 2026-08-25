import SwiftUI

struct DictationHUDView: View {
    let viewModel: DictationHUDViewModel

    var body: some View {
        HStack(spacing: DesignTokens.space16) {
            Image(systemName: viewModel.presentation.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.space4) {
                Text(viewModel.presentation.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                Text(viewModel.presentation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.space8)

            if viewModel.presentation.title == "Listening" {
                LevelBars(level: viewModel.level)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue(Int(viewModel.level * 100).description + " percent")
            } else if ["Transcribing", "Processing", "Inserting"].contains(viewModel.presentation.title) {
                ProgressView()
                    .controlSize(.small)
                    .tint(accentColor)
                    .accessibilityLabel(viewModel.presentation.title)
            }
        }
        .padding(.horizontal, DesignTokens.space16)
        .frame(width: DictationHUDController.panelSize.width, height: DictationHUDController.panelSize.height)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                .fill(DesignTokens.surfaceElevated.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var accentColor: Color {
        switch viewModel.presentation.accent {
        case .accent: DesignTokens.accent
        case .success: DesignTokens.success
        case .warning: DesignTokens.warning
        case .danger: DesignTokens.danger
        }
    }
}

private struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index < activeBarCount ? DesignTokens.accent : DesignTokens.border)
                    .frame(width: 3, height: CGFloat(10 + index % 3 * 6))
            }
        }
        .frame(width: 32, height: 34)
    }

    private var activeBarCount: Int {
        max(1, min(5, Int(ceil(level * 5))))
    }
}
