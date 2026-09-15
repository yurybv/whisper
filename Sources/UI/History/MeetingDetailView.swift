import SwiftUI

struct MeetingDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case result = "Result"
        var id: String { rawValue }
    }

    let meeting: MeetingSnapshot
    let segments: [TranscriptSegment]
    @State private var tab: Tab = .transcript

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                VStack(alignment: .leading, spacing: DesignTokens.space8) {
                    Text(meeting.title)
                        .font(.system(size: 24, weight: .semibold))
                    Text("\(meeting.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(duration(meeting.duration)) · \(meeting.historyStatus)")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.secondaryText)
                    if meeting.showsActiveProcessingProgress {
                        ProgressView(value: Double(meeting.progressCompleted), total: Double(meeting.progressTotal))
                            .accessibilityLabel("Processing progress")
                            .accessibilityValue("\(meeting.progressCompleted) of \(meeting.progressTotal)")
                    }
                }

                Picker("Recording content", selection: $tab) {
                    ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                if tab == .transcript {
                    TranscriptView(segments: segments)
                } else {
                    SettingsCard("Processed Result") {
                        Text(nonEmpty(meeting.processedText) ?? "No processed result is available.")
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SettingsCard("Processing Details", subtitle: meeting.resultLanguage ?? "Automatic result language") {
                    Text(meeting.instructionsSnapshot)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let error = meeting.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignTokens.warning)
                    }
                }
            }
            .padding(DesignTokens.space24)
        }
        .accessibilityIdentifier("Recording Detail")
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
