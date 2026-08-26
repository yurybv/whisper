# Milestone 2: End-to-end dictation

## WH-M2-001

- **Title:** Build OpenAI REST transport and retry policy
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Add centralized model configuration, URLSession transport, multipart audio upload, transcription/response DTOs, safe error mapping, and bounded retry/backoff.
- **Out of scope:** UI, audio capture, logging content, SDK dependencies, or real-network automated tests.
- **Acceptance criteria:** Requests stay below 20 MB; Authorization is never logged; invalid-key errors do not retry; transient errors follow the approved retry policy; fakes test all decoding and error paths.
- **Required checks:** OpenAI transport, multipart, DTO, and retry tests from implementation plan Task 5.
- **Dependencies:** WH-M1-005.
- **Expected files:** `Sources/OpenAI/**`, `Tests/WhisperTests/OpenAI/**`.
- **Source:** implementation plan Task 5.
- **Blockers:** None.

## WH-M2-002

- **Title:** Build microphone recorder and silence handling
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Implement protocol-backed AVAudioEngine recording, file output, metering, duration, device loss, silence/no-speech behavior, and cancellation cleanup.
- **Out of scope:** System audio and long meeting capture.
- **Acceptance criteria:** Short dictation audio is written deterministically; cancellation removes temporary files; device loss finalizes safely; silence yields a user-understandable result without uploading meaningless audio.
- **Required checks:** Recorder and silence tests from implementation plan Task 6; manual microphone smoke.
- **Dependencies:** WH-M1-005.
- **Expected files:** `Sources/Audio/MicrophoneRecorder.swift`, protocols/meters, matching tests.
- **Source:** implementation plan Task 6.
- **Blockers:** None.
- **Verification:** 12 focused audio tests and the 63-test unit suite pass without microphone permission. Live microphone smoke is not applicable until the recorder is wired into the dictation coordinator; the milestone review owns that end-to-end check.

## WH-M2-003

- **Title:** Implement mode transformation and dictation state machine
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Orchestrate record, transcribe, transform, insert-ready result, cancel, and failure states; snapshot the active mode and protect single-session concurrency.
- **Out of scope:** Actual Accessibility insertion and presentation UI.
- **Acceptance criteria:** State transitions are deterministic; only one dictation runs; Default preserves source language; custom instructions are applied without answering the dictated message; cancellation prevents insertion.
- **Required checks:** Dictation state-machine and transformation tests from implementation plan Task 7.
- **Dependencies:** WH-M2-001, WH-M2-002, WH-M1-003.
- **Expected files:** `Sources/Dictation/**`, matching tests.
- **Source:** implementation plan Task 7.
- **Blockers:** None.
- **Verification:** 10 focused prompt/coordinator tests and the full 73-test suite pass; the macOS application build succeeds. Manual target-app QA is not applicable until the protocol boundary is implemented and wired in WH-M2-004 and WH-M2-006.

## WH-M2-004

- **Title:** Capture focused target and insert text reliably
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Capture the previously focused process/element, restore focus, set text through Accessibility, and fall back to clipboard plus Command-V or clipboard-only.
- **Out of scope:** App-specific plugins and browser extensions.
- **Acceptance criteria:** Target app is captured before overlays; successful insertion restores the prior app; denied Accessibility copies result and explains manual paste; unsupported fields never lose the text.
- **Required checks:** Accessibility insertion tests from implementation plan Task 8; manual TextEdit, Notes, Safari, and VS Code matrix when available.
- **Dependencies:** WH-M2-003.
- **Expected files:** `Sources/Accessibility/**`, `Tests/WhisperTests/Accessibility/**`.
- **Source:** implementation plan Task 8.
- **Blockers:** None for implementation; Accessibility permission is required for the task's manual QA.
- **Verification:** Eight focused insertion tests and the full 81-test suite pass; the macOS application build succeeds. Test-first coverage verifies target capture order, direct AX insertion, paste fallback, full clipboard restoration, and clipboard preservation on every tested failure path. A fixed-marker service smoke previously passed in TextEdit, Notes, and Safari. VS Code and end-to-end focus QA remain with WH-M2-006/007 because the insertion service is not yet wired into the app; this verification run did not open user applications.

## WH-M2-005

- **Title:** Implement global shortcuts and shortcut recorder
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Implement CGEventTap listener, Right Option press/release semantics, Command-Shift-K, Command-Shift-R, Escape, editable shortcuts, and conflict handling.
- **Out of scope:** Mouse shortcuts and per-app shortcuts.
- **Acceptance criteria:** Right Option records only while held; release finishes; repeat events do not duplicate transitions; meeting disables push-to-talk; conflicts are detected before save.
- **Required checks:** Shortcut state-machine and recorder tests from implementation plan Task 9; manual shortcut smoke.
- **Dependencies:** WH-M2-003.
- **Expected files:** `Sources/Hotkeys/**`, matching tests.
- **Source:** implementation plan Task 9.
- **Blockers:** None for implementation; Input Monitoring or Accessibility permission may be required for the task's manual QA.
- **Verification:** Twenty-two focused state-machine, capture, conflict, actor-dispatch, and CGEvent normalization tests pass together with the full 103-test suite; the macOS application build succeeds. A real session event-tap smoke synthesized Right Option and observed exactly one pressed event followed by one released event without opening any user application.

## WH-M2-006

- **Title:** Build menu bar shell, HUD, and mode switcher
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Create menu bar commands, main-window opening, nonactivating HUD, key mode palette, and state presentation for listening through inserted/failed.
- **Out of scope:** Full Home/Modes/Settings content.
- **Acceptance criteria:** HUD never steals target focus; palette becomes key only while open and restores the prior app; all states use text plus icon, not color alone; menu actions mirror shortcuts.
- **Required checks:** View-model and panel lifecycle tests from implementation plan Task 10; keyboard/focus manual QA.
- **Dependencies:** WH-M2-003, WH-M2-004, WH-M2-005.
- **Expected files:** `Sources/WhisperApp/**`, `Sources/UI/HUD/**`, `Sources/UI/ModeSwitcher/**`, UI smoke tests.
- **Source:** implementation plan Task 10 and approved Open Design prototype.
- **Blockers:** None.
- **Verification:** Fifteen focused mode-switcher, HUD/panel lifecycle, menu-state, and responsive-cancellation tests pass together with the full 118-test unit suite; the app and UI-test targets compile successfully. Computer Use smoke verified the built dark mode palette focuses Search, supports keyboard navigation and Escape dismissal, restores the prior application without opening a main window, and leaves the menu utility running. A separate smoke displayed the text-and-icon Listening HUD over the active application without making a main window key. The local XCUITest runner was killed before bootstrapping a test process, so the same keyboard/focus paths were exercised through the built app's debug smoke hooks.

## WH-M2-007

- **Title:** Review end-to-end dictation milestone
- **Type:** review
- **Status:** in-progress
- **Priority:** P0
- **Scope:** Verify the real Default and Russian-to-English flows, target restoration, error recovery, shortcut behavior, network privacy, and test quality.
- **Out of scope:** Main settings UI and meetings.
- **Acceptance criteria:** End-to-end dictation passes in TextEdit; Default works in Russian and English; custom translation outputs English only; failed insertion preserves clipboard result; Milestone 3 is safe to start.
- **Required checks:** Full tests; manual dictation matrix subset; network/log secret scan; `git diff --check`.
- **Dependencies:** WH-M2-001 through WH-M2-006, WH-M2-008 through WH-M2-010.
- **Expected files:** `docs/implementation/reviews/m2-review.md`, backlog updates.
- **Source:** roadmap Milestone 2.
- **Blockers:** The production credential path and request contract are resolved by `WH-M2-008` through `WH-M2-010`; the final live TextEdit language matrix remains pending.

## WH-M2-008

- **Title:** Harden dictation failure recovery and completion feedback
- **Type:** fix
- **Status:** done
- **Priority:** P0
- **Scope:** Retain the complete failed dictation session, expose explicit retry and discard actions, preserve the original mode and target during retry, distinguish clipboard-only completion from inserted completion, and centralize secret-safe recovery messages for key, network, microphone, and insertion failures.
- **Out of scope:** Settings/onboarding UI, meeting recovery, relaunch persistence, History screens, or changes to the approved mode/transformation behavior.
- **Acceptance criteria:** Failed transcription or transformation can be retried without recording again; failed audio is deleted only after success or explicit discard; a new dictation cannot silently destroy recoverable work; clipboard-only completion says `Paste manually`; missing/invalid key and offline failures tell the owner what to do without exposing private content; coordinator-to-HUD regression tests cover the new paths.
- **Required checks:** Focused `FeatureError`, coordinator, HUD, menu-model, and runtime-action tests; full `WhisperTests`; application build; source logging/secret scan; `git diff --check`.
- **Dependencies:** WH-M2-001 through WH-M2-006.
- **Expected files:** `Sources/Core/FeatureError.swift`, `Sources/Dictation/**`, `Sources/UI/HUD/**`, `Sources/UI/MenuBar/**`, `Sources/WhisperApp/AppRuntime.swift`, matching tests, task/review docs.
- **Source:** approved design specification Error handling section and Milestone 2 review findings.
- **Blockers:** None.
- **Verification:** Retry resumes from the failed transcription, transformation, insertion, or history stage without recording again or duplicating completed insertion. Explicit Retry/Discard, deterministic discard-only failures, retained partial microphone capture, manual-paste feedback, secret-safe messages, and single-flight recovery actions are covered by tests. The full 138-test suite passes, the macOS app builds, production-source logging and credential-shape scans are clean, and `git diff --check` passes. Live recovery UI QA is not applicable without the production OpenAI Keychain credential and remains part of the resumed `WH-M2-007` TextEdit gate.

## WH-M2-009

- **Title:** Align transcription language metadata with the live OpenAI contract
- **Type:** fix
- **Status:** done
- **Priority:** P0
- **Scope:** Decode the live `gpt-transcribe` language metadata shape while retaining compatibility with the previously supported response field and keeping raw provider payloads out of logs.
- **Out of scope:** Model changes, request changes, diarized meeting responses, UI, or broader DTO refactoring.
- **Acceptance criteria:** A successful transcription response containing `languages[].code` decodes to `DetectedLanguage`; the legacy `languages[].language` fixture remains supported; live English and Russian audio requests no longer fail with `invalidResponse`; no response text or credential is logged.
- **Required checks:** Focused OpenAI DTO/client tests; opt-in live English/Russian QA; full `WhisperTests`; application build; source logging/secret scan; `git diff --check`.
- **Dependencies:** WH-M2-001.
- **Expected files:** `Sources/OpenAI/OpenAIModels.swift`, `Tests/WhisperTests/OpenAI/OpenAIClientTests.swift`, task/review docs.
- **Source:** `WH-M2-007` live OpenAI acceptance evidence.
- **Blockers:** None.
- **Verification:** A failing regression reproduced `invalidResponse` for the live `languages[].code` response shape, then passed after the decoder accepted `code` while preserving the legacy `language` field. All 13 focused OpenAI client tests pass. Temporary untracked live QA generated English and Russian WAV fixtures, received HTTP 200 from both transcription requests, verified Default retained English and Russian respectively, and verified the custom instruction returned English without Cyrillic. No credential, response text, transcript, or diagnostic payload value was printed or retained.

## WH-M2-010

- **Title:** Cache the OpenAI key for the active app session
- **Type:** fix
- **Status:** done
- **Priority:** P0
- **Scope:** Wrap the production Keychain store with a thread-safe, process-memory cache so a successfully read key is reused across transcription, transformation, retry, and connection-test requests during one app launch.
- **Out of scope:** `.env` or UserDefaults secrets, permissive Keychain ACLs, certificate provisioning, notarization, Settings UI, or persistence across app launches and rebuilds.
- **Acceptance criteria:** A nonempty key is fetched from the backing Keychain at most once per app session; missing values and read failures are not cached; save and delete keep the cache coherent; concurrent callers cannot trigger duplicate successful reads; the key remains absent from logs, files, task records, and test fixtures.
- **Required checks:** Focused secure-store tests including the initial expected failure; full `WhisperTests`; application build; production-source logging and credential-pattern scans; `git diff --check`.
- **Dependencies:** WH-M1-004, WH-M2-001.
- **Expected files:** `Sources/Core/SecureStore.swift`, `Sources/WhisperApp/AppRuntime.swift`, `Tests/WhisperTests/Core/KeychainSecureStoreTests.swift`, approved design/task/review documentation.
- **Source:** owner-approved Keychain session behavior on 2026-08-26 and the Milestone 2 live acceptance finding.
- **Blockers:** None. A stable no-prompt-across-builds experience still requires a persistent Apple signing identity in Milestone 6; this task safely removes repeated reads within the current app process.
- **Verification:** The initial cache test failed because `CachingSecureStore` did not exist. Save/delete lifecycle tests then failed until cache coherence was implemented. A deliberate read-outside-lock mutation made the concurrent regression fail and the restored single-flight implementation made it pass. Eight secure-store tests cover successful caching, nil/error/blank retry, concurrent reads, save, delete, in-memory lifecycle, and the real test-item Keychain lifecycle. The full 145-test suite and application build pass; environment, production logging, credential-shape, and `git diff --check` gates are clean. Manual Keychain UI QA is not applicable to deterministic cache behavior; macOS may still prompt once after an ad-hoc rebuild because its code requirement changes.
