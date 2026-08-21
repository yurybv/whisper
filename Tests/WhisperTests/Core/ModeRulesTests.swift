import XCTest
@testable import Whisper

final class ModeRulesTests: XCTestCase {
    func testRejectsBlankName() {
        let draft = ModeDraft(name: "  \n", instructions: "Translate", languageHint: nil)

        XCTAssertThrowsError(try ModeRules.validate(draft, existing: [])) {
            XCTAssertEqual($0 as? ModeValidationError, .blankName)
        }
    }

    func testRejectsTrimmedDuplicateName() {
        let existing = [
            ModeDefinition.defaultMode,
            ModeDefinition(
                id: UUID(),
                name: "English",
                instructions: "Translate",
                languageHint: nil,
                isDefault: false,
                isEnabled: true
            )
        ]
        let draft = ModeDraft(name: " english ", instructions: "Translate", languageHint: nil)

        XCTAssertThrowsError(try ModeRules.validate(draft, existing: existing)) {
            XCTAssertEqual($0 as? ModeValidationError, .duplicateName)
        }
    }

    func testRejectsBlankInstructions() {
        let draft = ModeDraft(name: "Translate", instructions: " \n ", languageHint: nil)

        XCTAssertThrowsError(try ModeRules.validate(draft, existing: [])) {
            XCTAssertEqual($0 as? ModeValidationError, .blankInstructions)
        }
    }

    func testDefaultModeIsStable() {
        XCTAssertTrue(ModeDefinition.defaultMode.isDefault)
        XCTAssertTrue(ModeDefinition.defaultMode.isEnabled)
        XCTAssertEqual(ModeDefinition.defaultMode.name, "Default")
        XCTAssertEqual(ModeDefinition.defaultMode.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(
            ModeDefinition.defaultMode.instructions,
            "Preserve the spoken language. Add punctuation and paragraphs. Remove obvious filler words and accidental repetitions. Correct obvious recognition errors. Preserve meaning, tone, technical terms, names, code identifiers, and abbreviations. Return only the final text."
        )
    }

    func testEditingDefaultModeIsRejected() {
        let draft = ModeDraft(
            id: ModeDefinition.defaultMode.id,
            name: "Renamed",
            instructions: "Changed",
            languageHint: nil
        )

        XCTAssertThrowsError(try ModeRules.validate(draft, existing: [ModeDefinition.defaultMode])) {
            XCTAssertEqual($0 as? ModeValidationError, .defaultMutation)
        }
    }

    func testDeletingDefaultModeIsRejected() {
        XCTAssertThrowsError(try ModeRules.validateDeletion(of: ModeDefinition.defaultMode)) {
            XCTAssertEqual($0 as? ModeValidationError, .defaultMutation)
        }
    }

    func testCustomModeValidatesAgainstItselfAndNormalizesFields() throws {
        let identifier = UUID()
        let existing = ModeDefinition(
            id: identifier,
            name: "English",
            instructions: "Translate",
            languageHint: "English",
            isDefault: false,
            isEnabled: true,
            sortIndex: 3
        )
        let draft = ModeDraft(
            id: identifier,
            name: " English ",
            instructions: " Translate to English \n",
            languageHint: " \n ",
            isEnabled: false,
            sortIndex: 3
        )

        let validated = try ModeRules.validate(draft, existing: [existing])

        XCTAssertEqual(validated.id, identifier)
        XCTAssertEqual(validated.name, "English")
        XCTAssertEqual(validated.instructions, "Translate to English")
        XCTAssertNil(validated.languageHint)
        XCTAssertFalse(validated.isEnabled)
        XCTAssertFalse(validated.isDefault)
        XCTAssertEqual(validated.sortIndex, 3)
    }

    func testModeDefinitionRoundTripsAllFieldsThroughJSON() throws {
        let mode = ModeDefinition(
            id: UUID(),
            name: " Russian to English ",
            instructions: "Translate the text.",
            languageHint: "Russian",
            isDefault: false,
            isEnabled: true,
            sortIndex: 2,
            createdAt: Date(timeIntervalSinceReferenceDate: 1),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2)
        )

        let data = try JSONEncoder().encode(mode)

        XCTAssertEqual(try JSONDecoder().decode(ModeDefinition.self, from: data), mode)
    }
}
