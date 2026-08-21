import Foundation
import SwiftData

@Model
final class ModeEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedName: String
    var name: String
    var instructions: String
    var languageHint: String?
    var isDefault: Bool
    var isEnabled: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ mode: ModeDefinition, normalizedName: String) {
        id = mode.id
        self.normalizedName = normalizedName
        name = mode.name
        instructions = mode.instructions
        languageHint = mode.languageHint
        isDefault = mode.isDefault
        isEnabled = mode.isEnabled
        sortIndex = mode.sortIndex
        createdAt = mode.createdAt
        updatedAt = mode.updatedAt
    }

    var definition: ModeDefinition {
        ModeDefinition(
            id: id,
            name: name,
            instructions: instructions,
            languageHint: languageHint,
            isDefault: isDefault,
            isEnabled: isEnabled,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(_ mode: ModeDefinition, normalizedName: String) {
        id = mode.id
        self.normalizedName = normalizedName
        name = mode.name
        instructions = mode.instructions
        languageHint = mode.languageHint
        isDefault = mode.isDefault
        isEnabled = mode.isEnabled
        sortIndex = mode.sortIndex
        createdAt = mode.createdAt
        updatedAt = mode.updatedAt
    }
}
