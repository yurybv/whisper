import SwiftUI

struct ModesListView: View {
    @Bindable var model: ModesModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ScreenHeader(
                        title: "Modes",
                        subtitle: "Shape dictated text with reusable instructions."
                    )
                    Spacer()
                    Button("Create Mode", systemImage: "plus") { model.beginCreate() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(DesignTokens.space24)

                Divider().overlay(DesignTokens.border)

                ScrollView {
                    LazyVStack(spacing: DesignTokens.space8) {
                        ForEach(model.modes) { mode in
                            modeRow(mode)
                        }
                    }
                    .padding(DesignTokens.space16)
                }
            }
            .frame(width: 390)
            .background(DesignTokens.surface)

            Divider().overlay(DesignTokens.border)

            Group {
                if let editor = model.editor {
                    ModeEditorView(model: model, editor: editor)
                } else {
                    ContentUnavailableView(
                        "Select a mode",
                        systemImage: "slider.horizontal.3",
                        description: Text("Choose a mode to inspect it, or create a custom mode.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.canvas)
        }
        .onAppear {
            model.reloadForPresentation()
            if model.editor == nil, let id = model.selectedModeID { model.select(id) }
        }
        .alert(
            "Delete \(model.pendingDeletion?.name ?? "mode")?",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.cancelDelete() } }
            )
        ) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { model.confirmDeleteForPresentation() }
        } message: {
            Text("This removes the mode permanently. Existing history keeps its saved mode snapshot.")
        }
    }

    private func modeRow(_ mode: ModeDefinition) -> some View {
        HStack(spacing: DesignTokens.space12) {
            Button { model.select(mode.id) } label: {
                HStack(spacing: DesignTokens.space12) {
                    Image(systemName: mode.id == model.activeModeID ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(mode.id == model.activeModeID ? DesignTokens.success : DesignTokens.mutedText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: DesignTokens.space8) {
                            Text(mode.name)
                                .font(.system(size: 14, weight: .semibold))
                            if mode.isDefault {
                                Text("BUILT-IN")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DesignTokens.mutedText)
                            }
                        }
                        Text(metadata(for: mode))
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.mutedText)
                    }
                    Spacer()
                    if !mode.isEnabled {
                        Text("Disabled")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.warning)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Mode row \(mode.name)")

            Menu {
                Button("Activate") { model.activateForPresentation(mode.id) }
                    .disabled(!mode.isEnabled || mode.id == model.activeModeID)
                Button("Duplicate") { model.duplicateForPresentation(mode.id) }
                if model.canRename(mode) {
                    Button("Rename") { model.beginRename(mode.id) }
                }
                if model.canDelete(mode) {
                    Divider()
                    Button("Delete", role: .destructive) { model.requestDelete(mode.id) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(mode.name)")
        }
        .padding(DesignTokens.space12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(model.selectedModeID == mode.id ? DesignTokens.selected : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.controlRadius)
                .stroke(model.selectedModeID == mode.id ? DesignTokens.border : .clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
    }

    private func metadata(for mode: ModeDefinition) -> String {
        let language = ModeInputLanguage(languageHint: mode.languageHint).label
        if mode.id == model.activeModeID { return "Active · \(language) input" }
        return "\(language) input · Updated \(mode.updatedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
