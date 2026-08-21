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
- **Status:** ready
- **Priority:** P0
- **Scope:** Capture the previously focused process/element, restore focus, set text through Accessibility, and fall back to clipboard plus Command-V or clipboard-only.
- **Out of scope:** App-specific plugins and browser extensions.
- **Acceptance criteria:** Target app is captured before overlays; successful insertion restores the prior app; denied Accessibility copies result and explains manual paste; unsupported fields never lose the text.
- **Required checks:** Accessibility insertion tests from implementation plan Task 8; manual TextEdit, Notes, Safari, Slack, and VS Code matrix when available.
- **Dependencies:** WH-M2-003.
- **Expected files:** `Sources/Accessibility/**`, `Tests/WhisperTests/Accessibility/**`.
- **Source:** implementation plan Task 8.
- **Blockers:** None for implementation; Accessibility permission is required for the task's manual QA.

## WH-M2-005

- **Title:** Implement global shortcuts and shortcut recorder
- **Type:** feature
- **Status:** ready
- **Priority:** P0
- **Scope:** Implement CGEventTap listener, Right Option press/release semantics, Command-Shift-K, Command-Shift-R, Escape, editable shortcuts, and conflict handling.
- **Out of scope:** Mouse shortcuts and per-app shortcuts.
- **Acceptance criteria:** Right Option records only while held; release finishes; repeat events do not duplicate transitions; meeting disables push-to-talk; conflicts are detected before save.
- **Required checks:** Shortcut state-machine and recorder tests from implementation plan Task 9; manual shortcut smoke.
- **Dependencies:** WH-M2-003.
- **Expected files:** `Sources/Hotkeys/**`, matching tests.
- **Source:** implementation plan Task 9.
- **Blockers:** None for implementation; Input Monitoring or Accessibility permission may be required for the task's manual QA.

## WH-M2-006

- **Title:** Build menu bar shell, HUD, and mode switcher
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Create menu bar commands, main-window opening, nonactivating HUD, key mode palette, and state presentation for listening through inserted/failed.
- **Out of scope:** Full Home/Modes/Settings content.
- **Acceptance criteria:** HUD never steals target focus; palette becomes key only while open and restores the prior app; all states use text plus icon, not color alone; menu actions mirror shortcuts.
- **Required checks:** View-model and panel lifecycle tests from implementation plan Task 10; keyboard/focus manual QA.
- **Dependencies:** WH-M2-003, WH-M2-004, WH-M2-005.
- **Expected files:** `Sources/WhisperApp/**`, `Sources/UI/HUD/**`, `Sources/UI/ModeSwitcher/**`, UI smoke tests.
- **Source:** implementation plan Task 10 and approved Open Design prototype.
- **Blockers:** WH-M2-003..005.

## WH-M2-007

- **Title:** Review end-to-end dictation milestone
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Verify the real Default and Russian-to-English flows, target restoration, error recovery, shortcut behavior, network privacy, and test quality.
- **Out of scope:** Main settings UI and meetings.
- **Acceptance criteria:** End-to-end dictation passes in TextEdit; Default works in Russian and English; custom translation outputs English only; failed insertion preserves clipboard result; Milestone 3 is safe to start.
- **Required checks:** Full tests; manual dictation matrix subset; network/log secret scan; `git diff --check`.
- **Dependencies:** WH-M2-001 through WH-M2-006.
- **Expected files:** `docs/implementation/reviews/m2-review.md`, backlog updates.
- **Source:** roadmap Milestone 2.
- **Blockers:** Completion of dictation tasks.
