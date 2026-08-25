import Foundation

enum ShortcutConflict: Error, Equatable, Sendable {
    case duplicate(ShortcutAction)
    case systemReserved
    case unmodifiedPrintable
}

enum ShortcutConflictDetector {
    static func conflict(
        for candidate: Shortcut,
        action: ShortcutAction,
        existing: [ShortcutAction: Shortcut]
    ) -> ShortcutConflict? {
        if let duplicate = ShortcutAction.allCases.first(where: { otherAction in
            otherAction != action && existing[otherAction] == candidate
        }) {
            return .duplicate(duplicate)
        }

        if candidate.modifiers == [.command],
           reservedCommandKeyCodes.contains(candidate.key.keyCode) {
            return .systemReserved
        }

        if candidate.modifiers.isEmpty,
           printableKeyCodes.contains(candidate.key.keyCode) {
            return .unmodifiedPrintable
        }

        return nil
    }

    private static let reservedCommandKeyCodes: Set<Int> = [4, 12, 13, 46]

    private static let printableKeyCodes: Set<Int> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
        31, 32, 33, 34, 35, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 49, 50
    ]
}
