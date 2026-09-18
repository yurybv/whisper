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

    func testBuiltInModesHaveStableIdentityOrderAndProtection() {
        XCTAssertEqual(
            ModeDefinition.builtInModes.map(\.id.uuidString),
            [
                "00000000-0000-0000-0000-000000000001",
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000003",
            ]
        )
        XCTAssertEqual(
            ModeDefinition.builtInModes.map(\.name),
            [
                "Default",
                "Russian → English — Work / Technical",
                "Russian → English — Slack / Friendly",
            ]
        )
        XCTAssertEqual(ModeDefinition.builtInModes.map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(ModeDefinition.builtInModes.map(\.languageHint), [nil, "ru", "ru"])
        XCTAssertTrue(ModeDefinition.builtInModes.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(ModeDefinition.builtInModes.filter(\.isDefault), [.defaultMode])
        XCTAssertEqual(
            ModeDefinition.russianEnglishWorkTechnicalMode.instructions,
            Self.workTechnicalInstructions
        )
        XCTAssertEqual(
            ModeDefinition.russianEnglishSlackFriendlyMode.instructions,
            Self.slackFriendlyInstructions
        )
    }

    func testEveryBuiltInRejectsEditingAndDeletionButDuplicatesRemainEditable() throws {
        for builtIn in ModeDefinition.builtInModes {
            let draft = ModeDraft(
                id: builtIn.id,
                name: "Changed",
                instructions: "Changed",
                languageHint: nil
            )
            XCTAssertThrowsError(try ModeRules.validate(draft, existing: ModeDefinition.builtInModes)) {
                XCTAssertEqual($0 as? ModeValidationError, .defaultMutation)
            }
            XCTAssertThrowsError(try ModeRules.validateDeletion(of: builtIn)) {
                XCTAssertEqual($0 as? ModeValidationError, .defaultMutation)
            }

            let duplicate = try ModeRules.validate(
                ModeDraft(
                    name: "\(builtIn.name) Copy",
                    instructions: builtIn.instructions,
                    languageHint: builtIn.languageHint
                ),
                existing: ModeDefinition.builtInModes
            )
            XCTAssertFalse(duplicate.isBuiltIn)
            XCTAssertFalse(duplicate.isDefault)
        }
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

    private static let workTechnicalInstructions = """
    Translate my spoken Russian into clear, natural, professional English.

    Act as an editor, not a literal translator.

    Rules:

    - Preserve the original meaning, technical details, and intent.
    - Remove filler words, repetitions, false starts, hesitation, and unnecessary phrases.
    - Fix fragmented spoken sentences and turn them into concise, well-structured English.
    - Do not translate Russian word order literally. Rewrite sentences the way a fluent English-speaking software engineer would naturally say them.
    - Keep the tone professional, direct, calm, and concise.
    - Prefer simple and precise English over sophisticated vocabulary.
    - Do not add explanations, assumptions, or information that I did not say.
    - Do not answer questions I dictate. Only transform and translate my speech.
    - Preserve technical terminology, product names, ticket IDs, URLs, code identifiers, package names, commands, and abbreviations.
    - Correct obvious speech-recognition mistakes using software-engineering context.
    - Use standard software-engineering vocabulary naturally: PR, review, deploy, staging, production, cache, API, frontend, backend, ticket, issue, implementation, etc.
    - If I correct myself while speaking, keep only the final intended version.
    - Avoid excessive politeness, filler, and corporate jargon.
    - Output only the final English text, ready to paste.
    """

    private static let slackFriendlyInstructions = """
    Translate my spoken Russian into natural, friendly English for workplace chats such as Slack.

    Act as an editor, not a literal translator.

    Rules:

    - Preserve my meaning and intent, but rewrite the message as natural conversational English.
    - Remove filler words, repetitions, hesitation, false starts, and unnecessary details.
    - If I ramble, make the message shorter while keeping the important information.
    - Do not translate Russian sentence structure literally.
    - Write like a friendly software engineer chatting with teammates.
    - Keep the tone warm, relaxed, polite, and collaborative.
    - Prefer short, simple sentences and everyday English.
    - Contractions are welcome when natural: I'll, I'm, don't, it's, we've, etc.
    - Light informal expressions are fine when appropriate.
    - Add 0–2 appropriate emojis when they make the message warmer or friendlier, such as 🙂 🙏 🚀 👀 👍, but do not overuse them.
    - For requests, prefer friendly phrasing rather than formal business language.
    - Preserve technical terminology, names, ticket IDs, PR numbers, URLs, code identifiers, and abbreviations.
    - Correct obvious speech-recognition mistakes using software-engineering context.
    - If I correct myself while speaking, keep only the final intended version.
    - Do not make the message unnecessarily formal or verbose.
    - Do not add information or promises that I did not say.
    - Do not answer my dictated message. Only transform and translate it.
    - Output only the final English message, ready to send in Slack.
    """
}
