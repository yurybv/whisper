# Milestone 5: History and retention

## WH-M5-001

- **Title:** Build unified history list and details
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Implement local History navigation, search, type filter, date grouping, statuses, dictation detail, recording detail, transcript/result tabs, and processing details.
- **Out of scope:** Cloud search, transcript editing, and individual speaker naming.
- **Acceptance criteria:** Dictations and recordings appear chronologically; search covers titles/transcript/result where safe; details expose mode/instruction snapshots and status; processing records remain inspectable after relaunch.
- **Required checks:** History query/view-model/UI tests from implementation plan Task 15; populated/empty/error screenshot comparison.
- **Dependencies:** WH-M4-006.
- **Expected files:** `Sources/UI/History/**`, repository query additions, UI tests.
- **Source:** implementation plan Task 15 and approved Open Design prototype.
- **Blockers:** None.
- **Implementation (2026-09-15):** Replaced the History placeholder with a unified local dictation/recording browser backed by complete SwiftData snapshots. Added deterministic newest-first Today/Yesterday/date groups, All/Dictations/Recordings filters, case-insensitive search across titles, instructions, original text, processed results, errors, target applications, and recording transcript segments. Added read-only dictation details plus recording Transcript/Result details with saved processing metadata, progress, retry-needed presentation, explicit empty/error states, selection reconciliation, and descriptive accessibility summaries. The runtime refreshes History on presentation, activation, and dictation/meeting state changes.
- **Verification:** 9 focused search, grouping, selection, persistence, retry-state, accessibility-summary, and populated/empty/error rendering tests passed. The final unit/service suite passed 274 of 274 tests with zero failures or skips; UI targets compiled without launch and the Debug app built. Three synthetic offscreen screenshots were visually inspected and retained under `docs/testing/evidence/WH-M5-001/`. `git diff --check`, privacy scan, and independent read-only review passed. Live UI automation was omitted under the owner's no-cursor instruction.

## WH-M5-002

- **Title:** Add playback, export, delete, and retention behavior
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Add recording playback, copy, plain-text export, confirmed delete, retention preference, and safe metadata/audio cleanup.
- **Out of scope:** Audio sharing, cloud backup, rich export formats, and automatic compression.
- **Acceptance criteria:** Playback selects available source/mix safely; export contains no API key or hidden metadata; delete removes only the selected record and directory; default retention is Forever; automatic cleanup never removes active/incomplete jobs.
- **Required checks:** Playback/export/delete/retention tests from implementation plan Task 15; filesystem containment tests; manual playback/export smoke.
- **Dependencies:** WH-M5-001.
- **Expected files:** `Sources/Audio/PlaybackService.swift`, history actions, retention service, matching tests.
- **Source:** implementation plan Task 15.
- **Blockers:** None.
- **Implementation (2026-09-15):** Added owned-source playback for microphone, system audio, and offset-aligned mixes without modifying originals; playback preparation is invalidated when its detail closes, selection/search/filter changes, deletion starts, or the app stops. History details now copy only the processed result, export a privacy-minimized plain-text document, and require confirmation before deleting. Meeting deletion atomically removes SwiftData metadata while creating a cleanup tombstone, removes only the exact UUID-owned directory, rejects traversal and symlink redirection, and retries failed file cleanup on launch. The approved MVP retention preference remains `Forever`, which performs no automatic history deletion while still retrying explicit cleanup tombstones.
- **Verification:** 24 focused playback/export/action/deletion/retention tests passed, including a real silent dual-M4A AVPlayer mix smoke, atomic text-file export, exact-directory and symlink containment, failed-cleanup relaunch retry, and pending-playback cancellation. The complete unit/service suite passed 290 of 290 tests; UI targets compiled without launch, the Debug app built and passed strict ad-hoc signature verification, `scripts/check-environment.sh` and `git diff --check` passed, and independent read-only review passed. Live XCUITest was omitted under the owner's no-cursor instruction; the service-level playback/export smoke required no UI or production data.

## WH-M5-003

- **Title:** Harden failure, retry, and cleanup behavior
- **Type:** testing
- **Status:** ready
- **Priority:** P0
- **Scope:** Verify and correct failed, retrying, interrupted, missing-file, corrupted-file, partial-track, and relaunch states across history and meeting processing.
- **Out of scope:** New recovery features beyond approved behavior.
- **Acceptance criteria:** Every recoverable state exposes a safe action; irrecoverable items preserve available evidence and explain the limitation; cleanup is idempotent; no retry duplicates transcript segments or processed results.
- **Required checks:** Failure-injection suite; relaunch tests; corrupted/missing-file tests; manual retry/reprocess smoke.
- **Dependencies:** WH-M5-001, WH-M5-002.
- **Expected files:** recovery tests and targeted fixes across `Sources/Meetings`, `Sources/Persistence`, and `Sources/UI/History`.
- **Source:** spec error handling and state machines.
- **Blockers:** None.

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
