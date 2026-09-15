# WH-M5-001 History verification

Date: 2026-09-15. Mac: Apple Silicon, macOS 26.4.1.

## Automated evidence

- `HistorySearchModelTests` cover unified newest-first ordering, All/Dictations/Recordings filters, case-insensitive search across titles, original text, processed results, and transcript segments, Today/Yesterday grouping, selected-detail fidelity, and load failure.
- `PersistenceTests.testHistorySnapshotReturnsFullRecordsAndChronologicalSegments` verifies that SwiftData returns complete dictation and recording snapshots plus ordered transcript segments.
- Offscreen SwiftUI tests render populated, empty, and error states at `1040 × 800` points without opening the application or moving focus.
- The UI test target compiles through `build-for-testing`; live XCUITest is intentionally omitted under the owner's no-cursor instruction.
- The final unit/service suite passed **274 of 274** tests with zero failures or skips. Result bundle: `/tmp/whisper-m5-001-final/Logs/Test/Test-Whisper-2026.09.15_12-46-57-+0400.xcresult`.
- The Debug application build, `git diff --check`, privacy logging scan, and independent read-only review passed.

## Visual evidence

- [Populated history](populated.png) shows search, type filters, Today/Yesterday groups, dictation and recording rows, selection, recording metadata, Transcript/Result tabs, chronological speaker labels, and the saved processing snapshot.
- [Empty history](empty.png) explains where new dictations and recordings will appear while preserving the details selection prompt.
- [History error](error.png) keeps the failure local to History and exposes a Try Again action without showing stale or private fallback content.

The screenshots use in-memory synthetic fixtures and contain no production history, transcript, instructions, API key, or network response.

## Scope and behavior

- History is read-only in this task. Playback, copy, export, delete, and retention remain isolated to `WH-M5-002`.
- The production runtime owns one history model, refreshes it on app activation and dictation/meeting state changes, and the History destination reloads from SwiftData when presented.
- Search and filters are local and case-insensitive. Date groups and row ordering use deterministic tie-breaking.
- Dictation details expose original and processed text, status, duration, mode/instruction snapshot, detected source record metadata, target application bundle ID, and errors when present.
- Recording details expose status, duration, progress, You/Others transcript timestamps, processed result, result language, saved instructions, and preserved error text.
