import Foundation

enum ShortcutAction: String, Sendable, Codable, CaseIterable {
    case pushToTalk
    case changeMode
    case recordMeeting
    case cancel
}

struct Shortcut: Sendable, Codable, Equatable {
    struct Key: Sendable, Codable, Equatable, Hashable {
        let keyCode: Int

        init(_ keyCode: Int) {
            self.keyCode = keyCode
        }

        static let rightOption = Key(61)
        static let k = Key(40)
        static let r = Key(15)
        static let escape = Key(53)
    }

    struct Modifiers: OptionSet, Sendable, Codable, Equatable, Hashable {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    let key: Key
    let modifiers: Modifiers

    init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}
