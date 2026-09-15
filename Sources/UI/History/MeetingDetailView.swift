import SwiftUI

struct MeetingDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case result = "Result"
        var id: String { rawValue }
    }

    let meeting: MeetingSnapshot
    let segments: [TranscriptSegment]
    var playbackSources: [MeetingPlaybackSource] = []
    var playingSource: MeetingPlaybackSource?
    var onPlay: (MeetingPlaybackSource) -> Void = { _ in }
    var onStop: () -> Void = {}
    var onCopy: () -> Void = {}
    var onExport: () -> Void = {}
    var onDelete: () -> Void = {}
    var canDelete = true
    var canCopy = true
    @State private var tab: Tab = .transcript
    @State private var selectedSource: MeetingPlaybackSource = .mix

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

                SettingsCard("Playback", subtitle: "Original source audio stays unchanged") {
                    if playbackSources.isEmpty {
                        Label("No playable source audio is available.", systemImage: "waveform.slash")
                            .foregroundStyle(DesignTokens.secondaryText)
                    } else {
                        HStack(spacing: DesignTokens.space8) {
                            Picker("Audio source", selection: $selectedSource) {
                                ForEach(playbackSources) { source in
                                    Text(source.rawValue).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                            if playingSource == nil {
                                Button("Play", systemImage: "play.fill") { onPlay(selectedSource) }
                            } else {
                                Button("Stop", systemImage: "stop.fill", action: onStop)
                            }
                        }
                    }
                    Divider().overlay(DesignTokens.border)
                    HStack(spacing: DesignTokens.space8) {
                        Button("Copy Result", systemImage: "doc.on.doc", action: onCopy)
                            .disabled(!canCopy)
                        Button("Export Text", systemImage: "square.and.arrow.up", action: onExport)
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                            .disabled(!canDelete)
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
        .onAppear { reconcilePlaybackSource() }
        .onChange(of: playbackSources) { reconcilePlaybackSource() }
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func reconcilePlaybackSource() {
        if !playbackSources.contains(selectedSource), let first = playbackSources.first {
            selectedSource = first
        }
    }
}
