import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space16) {
            VStack(alignment: .leading, spacing: DesignTokens.space4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.mutedText)
                }
            }
            content
        }
        .padding(DesignTokens.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                .stroke(DesignTokens.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }
}

struct KeycapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DesignTokens.secondaryText)
            .padding(.horizontal, DesignTokens.space8)
            .frame(minHeight: 24)
            .background(DesignTokens.surfaceCard)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DesignTokens.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space8) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DesignTokens.primaryText)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.secondaryText)
        }
    }
}
