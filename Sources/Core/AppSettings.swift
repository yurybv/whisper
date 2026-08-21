import Foundation

enum RetentionPolicy: String, Sendable, Codable, Equatable {
    case forever
}

struct AppSettings: Sendable, Codable, Equatable {
    let activeModeID: UUID?
    let selectedMicrophoneID: String?
    let shortcuts: [ShortcutAction: Shortcut]
    let recordingInstructions: String
    let resultLanguage: String?
    let launchAtLogin: Bool
    let soundEffects: Bool
    let retention: RetentionPolicy
    let onboardingCompleted: Bool

    init(
        activeModeID: UUID?,
        selectedMicrophoneID: String?,
        shortcuts: [ShortcutAction: Shortcut],
        recordingInstructions: String,
        resultLanguage: String?,
        launchAtLogin: Bool,
        soundEffects: Bool,
        retention: RetentionPolicy,
        onboardingCompleted: Bool
    ) {
        self.activeModeID = activeModeID
        self.selectedMicrophoneID = selectedMicrophoneID
        self.shortcuts = shortcuts
        self.recordingInstructions = recordingInstructions
        self.resultLanguage = resultLanguage
        self.launchAtLogin = launchAtLogin
        self.soundEffects = soundEffects
        self.retention = retention
        self.onboardingCompleted = onboardingCompleted
    }

    static let defaultRecordingInstructions = "Create clear meeting notes in English. Start with a concise summary. Then list decisions, action items with owner when stated, and open questions. Do not invent missing owners or deadlines. Preserve technical terminology."

    static let defaults = AppSettings(
        activeModeID: nil,
        selectedMicrophoneID: nil,
        shortcuts: [
            .pushToTalk: Shortcut(key: .rightOption, modifiers: [.option]),
            .changeMode: Shortcut(key: .k, modifiers: [.command, .shift]),
            .recordMeeting: Shortcut(key: .r, modifiers: [.command, .shift]),
            .cancel: Shortcut(key: .escape, modifiers: [])
        ],
        recordingInstructions: defaultRecordingInstructions,
        resultLanguage: nil,
        launchAtLogin: false,
        soundEffects: true,
        retention: .forever,
        onboardingCompleted: false
    )
}
