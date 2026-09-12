import Foundation

@MainActor
final class AppSettingsStore {
    private enum Key {
        static let selectedMicrophoneID = "selectedMicrophoneID"
        static let shortcuts = "shortcuts"
        static let soundEffects = "soundEffects"
        static let retention = "retention"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedMicrophoneID: String? {
        get { defaults.string(forKey: Key.selectedMicrophoneID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.selectedMicrophoneID)
            } else {
                defaults.removeObject(forKey: Key.selectedMicrophoneID)
            }
        }
    }

    var shortcuts: [ShortcutAction: Shortcut] {
        get {
            guard let data = defaults.data(forKey: Key.shortcuts),
                  let value = try? JSONDecoder().decode([ShortcutAction: Shortcut].self, from: data) else {
                return AppSettings.defaults.shortcuts
            }
            return AppSettings.defaults.shortcuts.merging(value) { _, stored in stored }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.shortcuts)
        }
    }

    var soundEffects: Bool {
        get {
            guard defaults.object(forKey: Key.soundEffects) != nil else {
                return AppSettings.defaults.soundEffects
            }
            return defaults.bool(forKey: Key.soundEffects)
        }
        set { defaults.set(newValue, forKey: Key.soundEffects) }
    }

    var retention: RetentionPolicy {
        get {
            guard let rawValue = defaults.string(forKey: Key.retention) else {
                return AppSettings.defaults.retention
            }
            return RetentionPolicy(rawValue: rawValue) ?? AppSettings.defaults.retention
        }
        set { defaults.set(newValue.rawValue, forKey: Key.retention) }
    }
}
