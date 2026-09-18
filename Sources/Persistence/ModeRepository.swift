import Foundation
import SwiftData

enum PersistenceError: Error, Sendable, Equatable {
    case modeNotFound
    case dictationNotFound
    case meetingNotFound
    case segmentMeetingMismatch
    case disabledMode
    case unsafePath
    case applicationSupportUnavailable
    case explicitStoreURLRequired
    case metadataMigrationFailed
}

extension PersistenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .metadataMigrationFailed:
            "Whisper could not safely migrate its local data. The original data was left unchanged."
        case .explicitStoreURLRequired:
            "Whisper could not determine where to store its local data."
        default:
            "Whisper could not access its local data."
        }
    }
}

@MainActor
final class ModeRepository {
    private let context: ModelContext
    private let userDefaults: UserDefaults
    private let activeModeKey: String

    init(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        activeModeKey: String = "activeModeID"
    ) {
        self.context = context
        self.userDefaults = userDefaults
        self.activeModeKey = activeModeKey
    }

    func seedBuiltInModes(now: Date = Date()) throws {
        var entities = try context.fetch(FetchDescriptor<ModeEntity>())

        for entity in entities where ModeDefinition.builtInIDs.contains(entity.id) {
            entity.normalizedName = "__whisper_builtin__\(entity.id.uuidString.lowercased())"
        }

        for builtIn in ModeDefinition.builtInModes {
            let canonicalName = normalizedName(builtIn.name)
            let collisions = entities.filter {
                !ModeDefinition.builtInIDs.contains($0.id)
                    && normalizedName($0.name) == canonicalName
            }
            for collision in collisions {
                let customName = uniqueCustomName(
                    for: builtIn.name,
                    excluding: collision.id,
                    entities: entities
                )
                collision.name = customName
                collision.normalizedName = normalizedName(customName)
                collision.updatedAt = now
            }

            if let entity = entities.first(where: { $0.id == builtIn.id }) {
                entity.apply(builtIn, normalizedName: canonicalName)
            } else {
                let entity = ModeEntity(builtIn, normalizedName: canonicalName)
                context.insert(entity)
                entities.append(entity)
            }
        }

        for entity in entities where entity.id != ModeDefinition.defaultMode.id {
            entity.isDefault = false
        }
        try context.save()
    }

    func fetchAll() throws -> [ModeDefinition] {
        let descriptor = FetchDescriptor<ModeEntity>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor).map(\.definition)
    }

    func create(_ draft: ModeDraft, now: Date = Date()) throws -> ModeDefinition {
        let mode = try ModeRules.validate(draft, existing: fetchAll(), now: now)
        context.insert(ModeEntity(mode, normalizedName: normalizedName(mode.name)))
        try context.save()
        return mode
    }

    func update(_ draft: ModeDraft, now: Date = Date()) throws -> ModeDefinition {
        guard let id = draft.id, let entity = try entity(id: id) else {
            throw PersistenceError.modeNotFound
        }
        let mode = try ModeRules.validate(draft, existing: fetchAll(), now: now)
        entity.apply(mode, normalizedName: normalizedName(mode.name))
        try context.save()
        return mode
    }

    func activate(_ id: UUID) throws {
        guard let mode = try entity(id: id) else {
            throw PersistenceError.modeNotFound
        }
        guard mode.isEnabled else {
            throw PersistenceError.disabledMode
        }
        userDefaults.set(id.uuidString, forKey: activeModeKey)
    }

    func activeMode() throws -> ModeDefinition {
        try seedBuiltInModes()

        if
            let value = userDefaults.string(forKey: activeModeKey),
            let id = UUID(uuidString: value),
            let mode = try entity(id: id),
            mode.isEnabled
        {
            return mode.definition
        }

        userDefaults.set(ModeDefinition.defaultMode.id.uuidString, forKey: activeModeKey)
        return ModeDefinition.defaultMode
    }

    func delete(_ id: UUID) throws {
        guard let mode = try entity(id: id) else {
            throw PersistenceError.modeNotFound
        }
        try ModeRules.validateDeletion(of: mode.definition)

        if userDefaults.string(forKey: activeModeKey) == id.uuidString {
            userDefaults.set(ModeDefinition.defaultMode.id.uuidString, forKey: activeModeKey)
        }
        context.delete(mode)
        try context.save()
    }

    private func entity(id: UUID) throws -> ModeEntity? {
        try context.fetch(FetchDescriptor<ModeEntity>()).first { $0.id == id }
    }

    private func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func uniqueCustomName(
        for builtInName: String,
        excluding excludedID: UUID,
        entities: [ModeEntity]
    ) -> String {
        var usedNames = Set(
            entities
                .filter { $0.id != excludedID }
                .map { normalizedName($0.name) }
        )
        usedNames.formUnion(ModeDefinition.builtInModes.map { normalizedName($0.name) })

        var suffix = 1
        while true {
            let label = suffix == 1 ? "Custom" : "Custom \(suffix)"
            let candidate = "\(builtInName) (\(label))"
            if !usedNames.contains(normalizedName(candidate)) {
                return candidate
            }
            suffix += 1
        }
    }
}
