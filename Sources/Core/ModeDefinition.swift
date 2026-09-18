import Foundation

struct ModeDefinition: Sendable, Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let instructions: String
    let languageHint: String?
    let isDefault: Bool
    let isEnabled: Bool
    let sortIndex: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        instructions: String,
        languageHint: String?,
        isDefault: Bool,
        isEnabled: Bool,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.languageHint = languageHint
        self.isDefault = isDefault
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultInstructions = "Preserve the spoken language. Add punctuation and paragraphs. Remove obvious filler words and accidental repetitions. Correct obvious recognition errors. Preserve meaning, tone, technical terms, names, code identifiers, and abbreviations. Return only the final text."

    static let defaultMode = ModeDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Default",
        instructions: defaultInstructions,
        languageHint: nil,
        isDefault: true,
        isEnabled: true,
        sortIndex: 0,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    static let russianEnglishWorkTechnicalMode = ModeDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Russian → English — Work / Technical",
        instructions: """
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
        """,
        languageHint: "ru",
        isDefault: false,
        isEnabled: true,
        sortIndex: 1,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    static let russianEnglishSlackFriendlyMode = ModeDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Russian → English — Slack / Friendly",
        instructions: """
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
        """,
        languageHint: "ru",
        isDefault: false,
        isEnabled: true,
        sortIndex: 2,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    static let builtInModes = [
        defaultMode,
        russianEnglishWorkTechnicalMode,
        russianEnglishSlackFriendlyMode,
    ]

    static let builtInIDs = Set(builtInModes.map(\.id))

    var isBuiltIn: Bool {
        Self.builtInIDs.contains(id)
    }
}

struct ModeDraft: Sendable, Equatable {
    let id: UUID?
    let name: String
    let instructions: String
    let languageHint: String?
    let isEnabled: Bool
    let sortIndex: Int

    init(
        id: UUID? = nil,
        name: String,
        instructions: String,
        languageHint: String?,
        isEnabled: Bool = true,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.languageHint = languageHint
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
    }
}
