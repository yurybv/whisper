import SwiftUI

struct ModeEditorView: View {
    @Bindable var model: ModesModel
    @Bindable var editor: ModeEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.space24) {
                ScreenHeader(
                    title: editor.modeID == nil ? "New Mode" : editor.name,
                    subtitle: editor.isDefault
                        ? "Whisper's built-in light cleanup mode."
                        : "Custom instructions run after transcription."
                )

                SettingsCard("Mode Details") {
                    labeledField("Mode name") {
                        TextField("Mode name", text: $editor.name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(editor.isDefault)
                            .accessibilityIdentifier("Mode name")
                    }

                    Divider().overlay(DesignTokens.border)

                    labeledField("Input language") {
                        Picker("Input language", selection: $editor.inputLanguage) {
                            ForEach(ModeInputLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(editor.isDefault)
                        .accessibilityLabel("Input language")
                        .accessibilityIdentifier("Input language")
                    }

                    if !editor.isDefault {
                        Divider().overlay(DesignTokens.border)
                        Toggle("Enabled", isOn: $editor.isEnabled)
                    }
                }

                SettingsCard(
                    "Custom Instructions",
                    subtitle: editor.isDefault
                        ? "Built-in instructions are protected."
                        : "Describe the transformation. Whisper will not answer or add facts."
                ) {
                    if editor.isDefault {
                        Text(editor.instructions)
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.secondaryText)
                            .textSelection(.enabled)
                    } else {
                        TextEditor(text: $editor.instructions)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(DesignTokens.space8)
                            .frame(minHeight: 220)
                            .background(DesignTokens.surfaceElevated)
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.controlRadius)
                                    .stroke(DesignTokens.border, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                            .accessibilityLabel("Custom instructions")
                            .accessibilityIdentifier("Custom instructions")
                    }
                }

                if let validationMessage = editor.validationMessage, editor.hasChanges {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.warning)
                }
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DesignTokens.danger)
                }

                HStack(spacing: DesignTokens.space12) {
                    if !editor.isDefault {
                        Button("Save Changes") { model.saveEditorForPresentation() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!editor.canSave)
                        Button("Cancel") { model.cancelEditing() }
                            .disabled(!editor.hasChanges)
                    }
                    Spacer()
                    if let id = editor.modeID {
                        if id != model.activeModeID, editor.isEnabled {
                            Button("Activate Mode") { model.activateForPresentation(id) }
                                .buttonStyle(.bordered)
                        } else if id == model.activeModeID {
                            Label("Active mode", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(DesignTokens.success)
                        }
                        Button("Duplicate Mode") { model.duplicateForPresentation(id) }
                            .buttonStyle(.bordered)
                        if !editor.isDefault {
                            Button("Delete Mode", role: .destructive) { model.requestDelete(id) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(DesignTokens.space32)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.space16) {
            Text(label)
                .foregroundStyle(DesignTokens.secondaryText)
                .frame(width: 120, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 36)
    }
}
