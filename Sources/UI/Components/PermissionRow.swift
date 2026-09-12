import SwiftUI

struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    var showRepair = false
    var repair: (() -> Void)?

    var body: some View {
        HStack(spacing: DesignTokens.space12) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(state == .granted ? DesignTokens.success : DesignTokens.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.settingsTitle)
                    .foregroundStyle(DesignTokens.primaryText)
                Text(state.setupLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.mutedText)
            }
            Spacer()
            if showRepair, let repair {
                Button("Open \(kind.settingsTitle) Settings", action: repair)
                    .buttonStyle(.bordered)
            }
        }
        .frame(minHeight: 44)
    }
}
