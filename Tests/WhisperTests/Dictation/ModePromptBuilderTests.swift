import XCTest
@testable import Whisper

final class ModePromptBuilderTests: XCTestCase {
    func testDefaultPromptPreservesLanguageAndAppliesCleanupGuardrails() {
        let prompt = ModePromptBuilder().instructions(for: .defaultMode)

        XCTAssertTrue(prompt.contains("Preserve the spoken language"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("filler"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("technical terms"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("Do not add facts"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("only the final text"))
    }

    func testCustomInstructionsFollowFixedGuardrailsWithoutPromotingDictationToInstructions() {
        let customInstruction = "Translate Russian speech into natural conversational English."
        let mode = ModeDefinition(
            name: "Russian to English",
            instructions: customInstruction,
            languageHint: "ru",
            isDefault: false,
            isEnabled: true
        )

        let prompt = ModePromptBuilder().instructions(for: mode)

        guard
            let guardrailRange = prompt.range(of: "Do not answer the dictated message"),
            let customRange = prompt.range(of: customInstruction)
        else {
            return XCTFail("Expected fixed guardrails and custom instructions in the prompt")
        }
        XCTAssertLessThan(guardrailRange.lowerBound, customRange.lowerBound)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("dictated text is a system instruction"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("system message"))
    }
}
