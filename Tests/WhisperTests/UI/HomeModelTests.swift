import XCTest
@testable import Whisper

@MainActor
final class HomeModelTests: XCTestCase {
    func testReadinessRequiresMicrophoneAndUsableAPIKey() {
        XCTAssertEqual(
            HomeReadiness.title(microphone: .denied, apiKey: .saved),
            "Dictation needs microphone access"
        )
        XCTAssertEqual(
            HomeReadiness.title(microphone: .granted, apiKey: .missing),
            "Dictation needs an OpenAI API key"
        )
        XCTAssertEqual(
            HomeReadiness.title(microphone: .granted, apiKey: .failed),
            "OpenAI connection needs attention"
        )
        XCTAssertEqual(
            HomeReadiness.title(microphone: .granted, apiKey: .connected),
            "Ready to dictate"
        )
    }

    func testReadinessExplainsLimitedGlobalKeyboardAccess() {
        let permissions = PermissionSnapshot(
            microphone: .granted,
            screenRecording: .denied,
            accessibility: .denied,
            inputMonitoring: .denied
        )

        XCTAssertEqual(
            HomeReadiness.subtitle(permissions: permissions, apiKey: .saved),
            "Dictation is ready here. Grant keyboard permissions for global shortcuts and direct insertion."
        )
    }

    func testRefreshShowsAtMostFiveLatestHistoryItems() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        for offset in 0..<6 {
            _ = try repository.createDictation(
                DictationDraft(
                    createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(offset)),
                    modeNameSnapshot: "Default",
                    modeInstructionsSnapshot: ModeDefinition.defaultInstructions,
                    outputText: "Output \(offset)",
                    status: .ready
                )
            )
        }
        let model = HomeModel(historyRepository: repository)

        model.refresh()

        XCTAssertEqual(model.recentHistory.count, 5)
        XCTAssertEqual(model.recentHistory.map(\.preview), ["Output 5", "Output 4", "Output 3", "Output 2", "Output 1"])
        XCTAssertNil(model.errorMessage)
    }
}
