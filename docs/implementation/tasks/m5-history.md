# Milestone 5: History and retention

## WH-M5-001

- **Title:** Build unified history list and details
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Implement local History navigation, search, type filter, date grouping, statuses, dictation detail, recording detail, transcript/result tabs, and processing details.
- **Out of scope:** Cloud search, transcript editing, and individual speaker naming.
- **Acceptance criteria:** Dictations and recordings appear chronologically; search covers titles/transcript/result where safe; details expose mode/instruction snapshots and status; processing records remain inspectable after relaunch.
- **Required checks:** History query/view-model/UI tests from implementation plan Task 15; populated/empty/error screenshot comparison.
- **Dependencies:** WH-M4-006.
- **Expected files:** `Sources/UI/History/**`, repository query additions, UI tests.
- **Source:** implementation plan Task 15 and approved Open Design prototype.
- **Blockers:** Previous milestone review.

## WH-M5-002

- **Title:** Add playback, export, delete, and retention behavior
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Add recording playback, copy, plain-text export, confirmed delete, retention preference, and safe metadata/audio cleanup.
- **Out of scope:** Audio sharing, cloud backup, rich export formats, and automatic compression.
- **Acceptance criteria:** Playback selects available source/mix safely; export contains no API key or hidden metadata; delete removes only the selected record and directory; default retention is Forever; automatic cleanup never removes active/incomplete jobs.
- **Required checks:** Playback/export/delete/retention tests from implementation plan Task 15; filesystem containment tests; manual playback/export smoke.
- **Dependencies:** WH-M5-001.
- **Expected files:** `Sources/Audio/PlaybackService.swift`, history actions, retention service, matching tests.
- **Source:** implementation plan Task 15.
- **Blockers:** WH-M5-001.

## WH-M5-003

- **Title:** Harden failure, retry, and cleanup behavior
- **Type:** testing
- **Status:** blocked
- **Priority:** P0
- **Scope:** Verify and correct failed, retrying, interrupted, missing-file, corrupted-file, partial-track, and relaunch states across history and meeting processing.
- **Out of scope:** New recovery features beyond approved behavior.
- **Acceptance criteria:** Every recoverable state exposes a safe action; irrecoverable items preserve available evidence and explain the limitation; cleanup is idempotent; no retry duplicates transcript segments or processed results.
- **Required checks:** Failure-injection suite; relaunch tests; corrupted/missing-file tests; manual retry/reprocess smoke.
- **Dependencies:** WH-M5-001, WH-M5-002.
- **Expected files:** recovery tests and targeted fixes across `Sources/Meetings`, `Sources/Persistence`, and `Sources/UI/History`.
- **Source:** spec error handling and state machines.
- **Blockers:** WH-M5-001..002.

## WH-M5-004

- **Title:** Review history and retention milestone
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Audit search/filter/detail correctness, source-file safety, export/privacy, deletion containment, retry idempotency, and UI state coverage.
- **Out of scope:** Packaging.
- **Acceptance criteria:** WH-M5-001..003 are done; no lifecycle state hides or loses recoverable data; Milestone 6 is safe to start.
- **Required checks:** Full tests; failure-injection suite; manual history matrix; `git diff --check`.
- **Dependencies:** WH-M5-001, WH-M5-002, WH-M5-003.
- **Expected files:** `docs/implementation/reviews/m5-review.md`, backlog updates.
- **Source:** roadmap Milestone 5.
- **Blockers:** Completion of history tasks.
