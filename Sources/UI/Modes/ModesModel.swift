import Foundation
import Observation

enum ModeInputLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case english
    case russian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .english: "English"
        case .russian: "Russian"
        }
    }

    var languageHint: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .russian: "ru"
        }
    }

    init(languageHint: String?) {
        switch languageHint {
        case "en": self = .english
        case "ru": self = .russian
        default: self = .automatic
        }
    }
}

@MainActor
@Observable
final class ModeEditorModel {
    let modeID: UUID?
    let isDefault: Bool
    var name: String
    var instructions: String
    var inputLanguage: ModeInputLanguage
    var isEnabled: Bool

    private let original: ModeDefinition?
    private let existingModes: [ModeDefinition]
    private let sortIndex: Int

    init(mode: ModeDefinition?, existingModes: [ModeDefinition], sortIndex: Int) {
        original = mode
        modeID = mode?.id
        isDefault = mode?.isDefault == true
        name = mode?.name ?? ""
        instructions = mode?.instructions ?? ""
        inputLanguage = ModeInputLanguage(languageHint: mode?.languageHint)
        isEnabled = mode?.isEnabled ?? true
        self.existingModes = existingModes
        self.sortIndex = mode?.sortIndex ?? sortIndex
    }

    var hasChanges: Bool {
        guard let original else {
            return !name.isEmpty || !instructions.isEmpty || inputLanguage != .automatic || !isEnabled
        }
        return name != original.name
            || instructions != original.instructions
            || inputLanguage.languageHint != original.languageHint
            || isEnabled != original.isEnabled
    }

    var validationMessage: String? {
        guard !isDefault else { return nil }
        do {
            _ = try validatedDraft()
            return nil
        } catch ModeValidationError.blankName {
            return "Enter a mode name."
        } catch ModeValidationError.duplicateName {
            return "A mode with this name already exists."
        } catch ModeValidationError.blankInstructions {
            return "Enter instructions for this mode."
        } catch {
            return "The Default mode cannot be changed."
        }
    }

    var canSave: Bool {
        !isDefault && hasChanges && validationMessage == nil
    }

    func validatedDraft() throws -> ModeDraft {
        let draft = ModeDraft(
            id: modeID,
            name: name,
            instructions: instructions,
            languageHint: inputLanguage.languageHint,
            isEnabled: isEnabled,
            sortIndex: sortIndex
        )
        _ = try ModeRules.validate(draft, existing: existingModes)
        return draft
    }
}

@MainActor
@Observable
final class ModesModel {
    private let repository: ModeRepository
    private var activeModeChanged: @MainActor (ModeDefinition) -> Void

    private(set) var modes: [ModeDefinition]
    private(set) var activeModeID: UUID
    private(set) var selectedModeID: UUID?
    private(set) var editor: ModeEditorModel?
    private(set) var pendingDeletion: ModeDefinition?
    private(set) var errorMessage: String?

    init(
        repository: ModeRepository,
        activeModeChanged: @escaping @MainActor (ModeDefinition) -> Void = { _ in }
    ) throws {
        self.repository = repository
        self.activeModeChanged = activeModeChanged
        modes = try repository.fetchAll()
        let activeMode = try repository.activeMode()
        activeModeID = activeMode.id
        selectedModeID = activeMode.id
        editor = nil
    }

    var selectedMode: ModeDefinition? {
        guard let selectedModeID else { return nil }
        return modes.first { $0.id == selectedModeID }
    }

    func setActiveModeChanged(_ callback: @escaping @MainActor (ModeDefinition) -> Void) {
        activeModeChanged = callback
    }

    func canRename(_ mode: ModeDefinition) -> Bool { !mode.isDefault }
    func canDelete(_ mode: ModeDefinition) -> Bool { !mode.isDefault }

    func reload() throws {
        modes = try repository.fetchAll()
        let activeMode = try repository.activeMode()
        activeModeID = activeMode.id
        if let selectedModeID, modes.contains(where: { $0.id == selectedModeID }) {
            self.selectedModeID = selectedModeID
        } else {
            selectedModeID = activeMode.id
        }
        activeModeChanged(activeMode)
    }

    func select(_ id: UUID) {
        guard let mode = modes.first(where: { $0.id == id }) else { return }
        selectedModeID = id
        editor = ModeEditorModel(
            mode: mode,
            existingModes: modes,
            sortIndex: mode.sortIndex
        )
        errorMessage = nil
    }

    func beginCreate() {
        selectedModeID = nil
        editor = ModeEditorModel(
            mode: nil,
            existingModes: modes,
            sortIndex: (modes.map(\.sortIndex).max() ?? 0) + 1
        )
        errorMessage = nil
    }

    func beginRename(_ id: UUID) {
        guard let mode = modes.first(where: { $0.id == id }), canRename(mode) else { return }
        select(id)
    }

    func cancelEditing() {
        if let selectedModeID, let mode = modes.first(where: { $0.id == selectedModeID }) {
            editor = ModeEditorModel(mode: mode, existingModes: modes, sortIndex: mode.sortIndex)
        } else {
            editor = nil
            selectedModeID = activeModeID
        }
        errorMessage = nil
    }

    func saveEditor() throws {
        guard let editor, editor.canSave else { return }
        let draft = try editor.validatedDraft()
        let saved = if draft.id == nil {
            try repository.create(draft)
        } else {
            try repository.update(draft)
        }
        try reload()
        select(saved.id)
    }

    func saveEditorForPresentation() {
        presentFailure("The mode could not be saved.") {
            try saveEditor()
        }
    }

    @discardableResult
    func duplicate(_ id: UUID) throws -> ModeDefinition {
        guard let source = modes.first(where: { $0.id == id }) else {
            throw PersistenceError.modeNotFound
        }
        let duplicate = try repository.create(
            ModeDraft(
                name: uniqueDuplicateName(for: source.name),
                instructions: source.instructions,
                languageHint: source.languageHint,
                isEnabled: source.isEnabled,
                sortIndex: (modes.map(\.sortIndex).max() ?? 0) + 1
            )
        )
        try reload()
        select(duplicate.id)
        return duplicate
    }

    func duplicateForPresentation(_ id: UUID) {
        presentFailure("The mode could not be duplicated.") {
            _ = try duplicate(id)
        }
    }

    func activate(_ id: UUID) throws {
        try repository.activate(id)
        try reload()
    }

    func activateForPresentation(_ id: UUID) {
        presentFailure("The mode could not be activated.") {
            try activate(id)
        }
    }

    func requestDelete(_ id: UUID) {
        guard let mode = modes.first(where: { $0.id == id }), canDelete(mode) else { return }
        pendingDeletion = mode
    }

    func cancelDelete() {
        pendingDeletion = nil
    }

    func confirmDelete() throws {
        guard let pendingDeletion else { return }
        try repository.delete(pendingDeletion.id)
        self.pendingDeletion = nil
        if selectedModeID == pendingDeletion.id {
            selectedModeID = nil
            editor = nil
        }
        try reload()
        if editor == nil, let active = modes.first(where: { $0.id == activeModeID }) {
            select(active.id)
        }
    }

    func confirmDeleteForPresentation() {
        presentFailure("The mode could not be deleted.") {
            try confirmDelete()
        }
    }

    func reloadForPresentation() {
        presentFailure("Modes could not be loaded.") {
            try reload()
        }
    }

    private func uniqueDuplicateName(for originalName: String) -> String {
        let used = Set(modes.map { $0.name.folding(options: [.caseInsensitive], locale: .current) })
        let base = "\(originalName) Copy"
        if !used.contains(base.folding(options: [.caseInsensitive], locale: .current)) {
            return base
        }
        var number = 2
        while used.contains("\(base) \(number)".folding(options: [.caseInsensitive], locale: .current)) {
            number += 1
        }
        return "\(base) \(number)"
    }

    private func presentFailure(_ message: String, action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = message
        }
    }
}
