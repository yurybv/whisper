import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Bindable var model: HistorySearchModel
    @State private var confirmsDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.space16) {
            ScreenHeader(
                title: "History",
                subtitle: "Search local dictations, recordings, transcripts, and processed results."
            )

            HStack(spacing: DesignTokens.space12) {
                TextField("Search history", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("Search History")
                Picker("History type", selection: $model.filter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            if let message = model.actionErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.warning)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let message = model.actionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.success)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HSplitView {
                historyList
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
                detail
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DesignTokens.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                    .stroke(DesignTokens.border, lineWidth: 1)
            }
        }
        .padding(DesignTokens.space32)
        .frame(maxWidth: DesignTokens.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.canvas)
        .onAppear { model.reload() }
        .alert("Delete selected history item?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { model.deleteSelectedForPresentation() }
        } message: {
            Text("This permanently removes the selected history record and its owned recording audio, if any.")
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { model.reload() }
            }
            .accessibilityIdentifier("History Error")
        } else if model.filteredEntries.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock.arrow.circlepath",
                description: Text(model.emptyMessage)
            )
            .accessibilityIdentifier("History Empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.space8) {
                    ForEach(model.groups) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.mutedText)
                            .textCase(.uppercase)
                            .padding(.horizontal, DesignTokens.space12)
                            .padding(.top, DesignTokens.space12)
                        ForEach(group.entries) { entry in
                            Button {
                                model.select(entry.id)
                            } label: {
                                HistoryEntryRow(entry: entry)
                                    .padding(.horizontal, DesignTokens.space12)
                                    .frame(minHeight: DesignTokens.rowHeight)
                                    .background(
                                        model.selectedID == entry.id
                                            ? DesignTokens.selected
                                            : .clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedID == entry.id ? .isSelected : [])
                        }
                    }
                }
                .padding(DesignTokens.space8)
            }
            .accessibilityIdentifier("History List")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = model.selectedEntry {
            switch entry.content {
            case let .dictation(dictation):
                DictationDetailView(
                    dictation: dictation,
                    onCopy: { model.copySelected() },
                    onExport: { presentExportPanel(for: entry) },
                    onDelete: { confirmsDelete = true },
                    canDelete: entry.canDelete,
                    canCopy: entry.hasCopyableResult
                )
            case let .recording(meeting, segments):
                MeetingDetailView(
                    meeting: meeting,
                    segments: segments,
                    playbackSources: model.playbackSources(for: meeting),
                    playingSource: model.playingMeetingID == meeting.id ? model.playingSource : nil,
                    onPlay: { source in Task { await model.play(meeting, source: source) } },
                    onStop: { model.stopPlayback() },
                    onRetry: { Task { await model.retrySelected() } },
                    onReprocess: { Task { await model.reprocessSelected() } },
                    onCopy: { model.copySelected() },
                    onExport: { presentExportPanel(for: entry) },
                    onDelete: { confirmsDelete = true },
                    canDelete: entry.canDelete,
                    canCopy: entry.hasCopyableResult,
                    canRetry: entry.canRetry && !model.isRecoveryActionRunning,
                    canReprocess: entry.canReprocess && !model.isRecoveryActionRunning
                )
                .id(meeting.id)
                .onDisappear { model.stopPlayback() }
            }
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a dictation or recording to inspect its saved details.")
            )
            .accessibilityIdentifier("History Detail Empty")
        }
    }

    private func presentExportPanel(for entry: HistoryEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = HistoryTextExporter.suggestedFilename(for: entry)
        panel.title = "Export History Text"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        model.exportSelectedForPresentation(to: destination)
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.space12) {
            Image(systemName: entry.filter == .dictations ? "waveform" : "rectangle.stack.badge.play")
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.space4) {
                HStack {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.mutedText)
                }
                Text(entry.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.secondaryText)
                    .lineLimit(2)
                Text(entry.status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.mutedText)
            }
        }
        .padding(.vertical, DesignTokens.space4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.accessibilitySummary)
    }
}
