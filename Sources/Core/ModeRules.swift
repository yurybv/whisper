import Foundation

enum ModeValidationError: Error, Sendable, Equatable {
    case blankName
    case duplicateName
    case blankInstructions
    case defaultMutation
}

enum ModeRules {
    static func validate(_ draft: ModeDraft, existing: [ModeDefinition], now: Date = Date()) throws -> ModeDefinition {
        if draft.id == ModeDefinition.defaultMode.id || existing.contains(where: { $0.id == draft.id && $0.isDefault }) {
            throw ModeValidationError.defaultMutation
        }

        let name = trim(draft.name)
        guard !name.isEmpty else {
            throw ModeValidationError.blankName
        }

        let instructions = trim(draft.instructions)
        guard !instructions.isEmpty else {
            throw ModeValidationError.blankInstructions
        }

        if existing.contains(where: { mode in
            mode.id != draft.id && normalizedName(mode.name) == normalizedName(name)
        }) {
            throw ModeValidationError.duplicateName
        }

        let existingMode = existing.first(where: { $0.id == draft.id })
        return ModeDefinition(
            id: draft.id ?? UUID(),
            name: name,
            instructions: instructions,
            languageHint: normalizedLanguageHint(draft.languageHint),
            isDefault: false,
            isEnabled: draft.isEnabled,
            sortIndex: draft.sortIndex,
            createdAt: existingMode?.createdAt ?? now,
            updatedAt: now
        )
    }

    static func validateDeletion(of mode: ModeDefinition) throws {
        if mode.isDefault || mode.id == ModeDefinition.defaultMode.id {
            throw ModeValidationError.defaultMutation
        }
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedName(_ value: String) -> String {
        trim(value).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func normalizedLanguageHint(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = trim(value)
        return normalized.isEmpty ? nil : normalized
    }
}
