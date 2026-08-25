import SwiftUI

struct ModeSwitcherView: View {
    let viewModel: ModeSwitcherViewModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.space12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.mutedText)
                    .accessibilityHidden(true)
                TextField("Search modes", text: queryBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DesignTokens.primaryText)
                    .focused($searchIsFocused)
                    .accessibilityLabel("Search modes")
            }
            .padding(.horizontal, DesignTokens.space16)
            .frame(height: 56)

            Divider().overlay(DesignTokens.border)

            ScrollView {
                LazyVStack(spacing: DesignTokens.space4) {
                    ForEach(viewModel.modes) { mode in
                        modeRow(mode)
                    }

                    if viewModel.modes.isEmpty {
                        ContentUnavailableView(
                            "No modes found",
                            systemImage: "magnifyingglass",
                            description: Text("Try another search.")
                        )
                        .foregroundStyle(DesignTokens.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(DesignTokens.space8)
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(DesignTokens.border)

            HStack(spacing: DesignTokens.space16) {
                shortcutHint("↑↓", "Navigate")
                shortcutHint("↩", "Activate")
                shortcutHint("esc", "Close")
                Spacer()
            }
            .padding(.horizontal, DesignTokens.space16)
            .frame(height: 44)
        }
        .frame(width: 560, height: 420)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                .fill(DesignTokens.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.overlayRadius, style: .continuous))
        .onAppear { searchIsFocused = true }
        .onKeyPress(.upArrow) {
            viewModel.move(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.move(.down)
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.activateSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.close()
            return .handled
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.query },
            set: { viewModel.query = $0 }
        )
    }

    private func modeRow(_ mode: ModeDefinition) -> some View {
        Button {
            viewModel.select(mode.id)
            viewModel.activateSelection()
        } label: {
            HStack(spacing: DesignTokens.space12) {
                Image(systemName: mode.id == viewModel.activeModeID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode.id == viewModel.activeModeID ? DesignTokens.success : DesignTokens.mutedText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.primaryText)
                    if let languageHint = mode.languageHint, !languageHint.isEmpty {
                        Text("Language hint: \(languageHint.uppercased())")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.mutedText)
                    }
                }
                Spacer()
                if mode.id == viewModel.selectedModeID {
                    Text("↩")
                        .foregroundStyle(DesignTokens.mutedText)
                }
            }
            .padding(.horizontal, DesignTokens.space12)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius)
                    .fill(mode.id == viewModel.selectedModeID ? DesignTokens.selected : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.name)
        .accessibilityValue(mode.id == viewModel.activeModeID ? "Active" : "")
    }

    private func shortcutHint(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: DesignTokens.space4) {
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DesignTokens.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(DesignTokens.mutedText)
    }
}
