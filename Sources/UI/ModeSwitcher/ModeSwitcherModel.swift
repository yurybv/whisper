import Foundation

struct ModeSwitcherModel: Equatable {
    enum SelectionDirection: Equatable {
        case up
        case down
    }

    enum Command: Equatable {
        case activate
        case close
    }

    enum Action: Equatable {
        case activate(UUID)
        case close
    }

    private let modes: [ModeDefinition]
    let activeModeID: UUID
    private(set) var selectedModeID: UUID?

    var query = "" {
        didSet {
            normalizeSelection()
        }
    }

    init(modes: [ModeDefinition], activeModeID: UUID) {
        self.modes = modes
            .filter(\.isEnabled)
            .sorted {
                if $0.sortIndex == $1.sortIndex {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortIndex < $1.sortIndex
            }
        self.activeModeID = activeModeID
        selectedModeID = self.modes.contains(where: { $0.id == activeModeID })
            ? activeModeID
            : self.modes.first?.id
    }

    var filteredModes: [ModeDefinition] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return modes }
        return modes.filter { mode in
            mode.name.localizedCaseInsensitiveContains(trimmedQuery)
                || (mode.languageHint?.localizedCaseInsensitiveContains(trimmedQuery) == true)
        }
    }

    var selectedMode: ModeDefinition? {
        guard let selectedModeID else { return nil }
        return filteredModes.first { $0.id == selectedModeID }
    }

    mutating func moveSelection(_ direction: SelectionDirection) {
        let availableModes = filteredModes
        guard !availableModes.isEmpty else {
            selectedModeID = nil
            return
        }
        guard
            let selectedModeID,
            let index = availableModes.firstIndex(where: { $0.id == selectedModeID })
        else {
            self.selectedModeID = availableModes.first?.id
            return
        }

        switch direction {
        case .up:
            self.selectedModeID = availableModes[(index - 1 + availableModes.count) % availableModes.count].id
        case .down:
            self.selectedModeID = availableModes[(index + 1) % availableModes.count].id
        }
    }

    func handle(_ command: Command) -> Action? {
        switch command {
        case .activate:
            selectedMode.map { .activate($0.id) }
        case .close:
            .close
        }
    }

    mutating func select(_ id: UUID) {
        guard filteredModes.contains(where: { $0.id == id }) else { return }
        selectedModeID = id
    }

    private mutating func normalizeSelection() {
        let availableModes = filteredModes
        guard !availableModes.isEmpty else {
            selectedModeID = nil
            return
        }
        if let selectedModeID, availableModes.contains(where: { $0.id == selectedModeID }) {
            return
        }
        selectedModeID = availableModes.first?.id
    }
}
