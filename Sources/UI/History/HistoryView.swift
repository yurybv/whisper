import SwiftUI

struct HistoryView: View {
    @Bindable var model: HistorySearchModel

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
                DictationDetailView(dictation: dictation)
            case let .recording(meeting, segments):
                MeetingDetailView(meeting: meeting, segments: segments)
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
