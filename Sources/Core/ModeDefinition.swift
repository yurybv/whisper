import Foundation

struct ModeDefinition: Sendable, Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let instructions: String
    let languageHint: String?
    let isDefault: Bool
    let isEnabled: Bool
    let sortIndex: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        instructions: String,
        languageHint: String?,
        isDefault: Bool,
        isEnabled: Bool,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.languageHint = languageHint
        self.isDefault = isDefault
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultInstructions = "Preserve the spoken language. Add punctuation and paragraphs. Remove obvious filler words and accidental repetitions. Correct obvious recognition errors. Preserve meaning, tone, technical terms, names, code identifiers, and abbreviations. Return only the final text."

    static let defaultMode = ModeDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Default",
        instructions: defaultInstructions,
        languageHint: nil,
        isDefault: true,
        isEnabled: true,
        sortIndex: 0,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

struct ModeDraft: Sendable, Equatable {
    let id: UUID?
    let name: String
    let instructions: String
    let languageHint: String?
    let isEnabled: Bool
    let sortIndex: Int

    init(
        id: UUID? = nil,
        name: String,
        instructions: String,
        languageHint: String?,
        isEnabled: Bool = true,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.languageHint = languageHint
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
    }
}
