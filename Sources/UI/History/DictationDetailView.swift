import SwiftUI

struct DictationDetailView: View {
    let dictation: DictationSnapshot
    var onCopy: () -> Void = {}
    var onExport: () -> Void = {}
    var onDelete: () -> Void = {}
    var canDelete = true
    var canCopy = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                detailHeader
                HStack(spacing: DesignTokens.space8) {
                    Button("Copy Result", systemImage: "doc.on.doc", action: onCopy)
                        .disabled(!canCopy)
                    Button("Export Text", systemImage: "square.and.arrow.up", action: onExport)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .disabled(!canDelete)
                }
                SettingsCard("Original Transcript") {
                    detailText(dictation.originalText, empty: "No original transcript is available.")
                }
                SettingsCard("Processed Result") {
                    detailText(dictation.outputText, empty: "No processed result is available.")
                }
                SettingsCard("Mode Snapshot", subtitle: dictation.modeNameSnapshot) {
                    detailText(dictation.modeInstructionsSnapshot, empty: "No saved instructions.")
                    if let bundleID = dictation.targetApplicationBundleID {
                        Label(bundleID, systemImage: "app")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.secondaryText)
                    }
                }
                if let error = dictation.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.warning)
                }
            }
            .padding(DesignTokens.space24)
        }
        .accessibilityIdentifier("Dictation Detail")
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space8) {
            Text(dictation.modeNameSnapshot)
                .font(.system(size: 24, weight: .semibold))
            Text("\(dictation.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(duration(dictation.duration)) · \(dictation.status.rawValue.capitalized)")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.secondaryText)
        }
    }

    private func detailText(_ text: String, empty: String) -> some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? empty : text)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
