import XCTest
@testable import Whisper

final class ShortcutTests: XCTestCase {
    func testArbitraryShortcutKeyRoundTripsThroughJSON() throws {
        let value = Shortcut(key: Shortcut.Key(123), modifiers: [.command, .control])

        let data = try JSONEncoder().encode(value)

        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), value)
    }

    func testDefaultShortcutsRoundTripThroughJSON() throws {
        let values = AppSettings.defaults.shortcuts
        let data = try JSONEncoder().encode(values)

        XCTAssertEqual(try JSONDecoder().decode([ShortcutAction: Shortcut].self, from: data), values)
    }

    func testDefaultShortcutsUseApprovedKeysAndModifiers() {
        XCTAssertEqual(AppSettings.defaults.shortcuts, [
            .pushToTalk: Shortcut(key: .rightOption, modifiers: [.option]),
            .changeMode: Shortcut(key: .k, modifiers: [.command, .shift]),
            .recordMeeting: Shortcut(key: .r, modifiers: [.command, .shift]),
            .cancel: Shortcut(key: .escape, modifiers: [])
        ])
    }

    func testDefaultSettingsUseApprovedValues() {
        let settings = AppSettings.defaults

        XCTAssertNil(settings.activeModeID)
        XCTAssertNil(settings.selectedMicrophoneID)
        XCTAssertEqual(settings.recordingInstructions, "Create clear meeting notes in English. Start with a concise summary. Then list decisions, action items with owner when stated, and open questions. Do not invent missing owners or deadlines. Preserve technical terminology.")
        XCTAssertNil(settings.resultLanguage)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.soundEffects)
        XCTAssertEqual(settings.retention, .forever)
        XCTAssertFalse(settings.onboardingCompleted)
    }

    func testCompleteSettingsRoundTripThroughJSON() throws {
        let settings = AppSettings(
            activeModeID: UUID(),
            selectedMicrophoneID: "BuiltInMicrophoneDevice",
            shortcuts: [
                .pushToTalk: Shortcut(key: .rightOption, modifiers: [.option]),
                .changeMode: Shortcut(key: Shortcut.Key(123), modifiers: [.control]),
                .recordMeeting: Shortcut(key: .r, modifiers: [.command, .shift]),
                .cancel: Shortcut(key: .escape, modifiers: [])
            ],
            recordingInstructions: "Summarize this meeting.",
            resultLanguage: "Russian",
            launchAtLogin: true,
            soundEffects: false,
            retention: .forever,
            onboardingCompleted: true
        )

        let data = try JSONEncoder().encode(settings)

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }
}
