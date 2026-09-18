# Whisper Release Stabilization Design

Date: 2026-09-18
Status: owner-approved release follow-up
Audience: agentic implementation workers

## Context

Foreground acceptance of the packaged personal build exposed four release blockers and one requested preset expansion:

1. Warp returns `AXError.success` for selected-text replacement without changing its terminal input, so Whisper reports `Inserted` while no text appears.
2. Repeating the Change Mode shortcut while the switcher is open should move to the next mode without requiring an arrow key.
3. The activation circle in the Modes list looks interactive but only selects the row; activation is hidden in the ellipsis menu.
4. SwiftData currently chooses the generic unsandboxed path `~/Library/Application Support/default.store`. Rebuilt or separately launched applications can therefore collide with or replace Whisper metadata. The current store contains one mode and no history records, so the previously observed history and custom modes are not recoverable from that store.
5. Two owner-supplied Russian-to-English presets should ship with the app alongside Default.

This document is an approved delta to `2026-08-19-whisper-macos-mvp-design.md`. Requirements not changed here remain in force.

## Reliable insertion in Warp

Whisper continues to capture the target process, bundle identifier, and focused Accessibility element when dictation begins. Direct `kAXSelectedTextAttribute` replacement remains preferred for normal editable controls.

`dev.warp.Warp-Stable` is a known false-positive target: Whisper must skip direct replacement and use the existing clipboard paste path. The service activates the captured Warp process, snapshots every pasteboard representation, writes the processed result, posts Command-V, waits for the existing paste handoff delay, and restores the prior pasteboard. Failure to activate or post paste leaves the processed result on the clipboard and reports manual paste instead of `Inserted`.

The behavior is bundle-policy driven so additional verified false-positive applications can be added without changing dictation coordination.

## Stable metadata storage and legacy adoption

SwiftData metadata belongs at:

```text
~/Library/Application Support/Whisper/Metadata/Whisper.store
```

The location is independent of the app bundle path, build configuration, App Translocation, or installation under `/Applications`.

Before the first canonical container opens:

1. If the canonical store exists, use it and never replace it from legacy data.
2. Otherwise, inspect `~/Library/Application Support/default.store` without reading or logging user content.
3. If its persistent-store metadata identifies the complete Whisper entity schema, copy the SQLite store family into a staging directory under `Application Support/Whisper`, atomically promote that directory to `Metadata`, then open and validate the canonical store.
4. Keep the legacy store untouched as rollback evidence. Do not delete it automatically.
5. If migration of a compatible Whisper store fails, fail startup with the existing local-storage error instead of silently creating an empty database.
6. If no compatible legacy Whisper store exists, create a new canonical store.

Tests use synthetic metadata only. Production diagnostics must never print mode instructions, dictated text, transcripts, or paths that reveal user content.

## Built-in modes

Three protected modes ship with stable UUIDs and deterministic ordering:

1. `Default`
2. `Russian → English — Work / Technical`
3. `Russian → English — Slack / Friendly`

All three are enabled, protected from rename/delete/edit, and available for duplication. Default remains the fallback and the active mode on a clean installation. Existing active selections remain active when their mode still exists.

The Work / Technical preset uses Russian input (`ru`) and this exact instruction:

```text
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
```

The Slack / Friendly preset uses Russian input (`ru`) and this exact instruction:

```text
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
```

Seeding is idempotent and runs on every application startup. It upserts canonical built-ins by stable ID, repairs changed canonical content, preserves user-created modes, and does not reset the current active mode. If a custom mode already owns an exact built-in name, preserve its ID and content under a deterministic ` (Custom)` suffix before adding the canonical preset.

## Mode interactions

The global Change Mode shortcut behaves as follows:

- when the switcher is closed, Control-Command-M opens it with the active mode selected;
- while it is open, each repeated Control-Command-M moves selection to the next filtered enabled mode and wraps at the end;
- Up/Down remain equivalent navigation controls;
- Return activates the selected mode and closes the panel;
- Escape closes without activation and restores the previous application;
- the footer displays `⌃⌘M Next`, `↑↓ Navigate`, `↩ Activate`, and `esc Close`.

Home and menu-bar Change Mode actions only open the panel; they do not synthesize a second navigation step.

In the Modes list, the leading circle is a dedicated 44-point activation button. Clicking the rest of the row selects it for inspection. `Activate` is removed from the ellipsis menu; Duplicate, Rename, and Delete retain their existing eligibility rules. The right-side `Activate Mode` action remains available. VoiceOver exposes the circle as `Activate <mode name>` and reports the active state without relying on color.

## Verification and privacy

Each follow-up uses TDD and focused tests before the full `./scripts/verify.sh` gate. Manual acceptance uses generated phrases only and covers Warp plus the original TextEdit, Notes, Safari, and VS Code targets. Store migration tests use temporary synthetic stores and never open the production store. No evidence contains an API key, dictated content, transcript, or custom instruction.
