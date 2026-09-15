import SwiftUI

struct TranscriptView: View {
    let segments: [TranscriptSegment]

    var body: some View {
        SettingsCard("Transcript", subtitle: "Chronological speaker timeline") {
            if segments.isEmpty {
                Text("No transcript is available yet.")
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                LazyVStack(alignment: .leading, spacing: DesignTokens.space16) {
                    ForEach(segments) { segment in
                        HStack(alignment: .top, spacing: DesignTokens.space12) {
                            Text(timestamp(segment.startTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(DesignTokens.mutedText)
                                .frame(width: 62, alignment: .leading)
                            VStack(alignment: .leading, spacing: DesignTokens.space4) {
                                Text(segment.source == .you ? "You" : "Others")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(segment.source == .you ? DesignTokens.accent : DesignTokens.success)
                                Text(segment.text)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }
}
