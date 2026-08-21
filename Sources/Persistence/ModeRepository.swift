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

    func seedDefaultMode() throws {
        let entities = try context.fetch(FetchDescriptor<ModeEntity>())
        let canonicalID = ModeDefinition.defaultMode.id
        let candidates = entities.filter { $0.isDefault || $0.id == canonicalID }

        if let keeper = candidates.first(where: { $0.id == canonicalID }) ?? candidates.first {
            keeper.apply(ModeDefinition.defaultMode, normalizedName: normalizedName(ModeDefinition.defaultMode.name))
            for duplicate in candidates where duplicate !== keeper {
                context.delete(duplicate)
            }
        } else {
            context.insert(
                ModeEntity(
                    ModeDefinition.defaultMode,
                    normalizedName: normalizedName(ModeDefinition.defaultMode.name)
                )
            )
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
        try seedDefaultMode()

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
}
