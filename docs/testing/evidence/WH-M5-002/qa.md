# WH-M5-002 History actions verification

Date: 2026-09-15. Mac: Apple Silicon, macOS 26.4.1.

## Automated evidence

- `AudioPlaybackServiceTests` verify source availability, exact meeting ownership, saved offsets, unchanged originals, unavailable-source handling, stop forwarding, and a real silent dual-M4A mix prepared through the production AVPlayer transport.
- `HistoryActionTests` verify privacy-minimized plain-text documents, result-only clipboard content, explicit missing-result behavior, safe filenames, and atomic UTF-8 export.
- `RetentionServiceTests` verify `Forever` performs no automatic history deletion, manual deletion removes only the selected SwiftData record and exact UUID-owned directory, filesystem failure leaves a durable tombstone, launch cleanup retries it, and traversal, wrong-meeting paths, and symlink redirection are rejected.
- `HistorySearchModelTests` verify actions stay scoped to the selected entry and both active and pending playback stop when selection, search, or filter hides the recording.
- The focused action suite passed **24 of 24** tests. The final unit/service suite passed **290 of 290** tests with zero failures.
- UI targets compiled through `build-for-testing` without launch. The Debug app build, strict ad-hoc signature verification, environment check, `git diff --check`, privacy scan, and independent read-only review passed.

## Service-level smoke

- Playback smoke generated two synthetic silent M4A tracks, built an offset-aligned mix through `AVPlayerPlaybackTransport`, started it, and stopped it without changing either source file.
- Export smoke wrote a synthetic history record to a temporary plain-text file, read it back byte-for-byte, and verified that internal IDs, storage paths, processing instructions, target application metadata, and failure metadata were absent.
- Live application/XCUITest interaction was intentionally omitted under the owner's no-cursor instruction. No app window was launched and no production audio, history, Keychain value, permission state, or network service was accessed.

## Retention and cleanup behavior

- The approved MVP preference remains `Forever`; it never automatically removes a ready, active, incomplete, failed, or interrupted history record.
- Confirmed meeting deletion creates a SwiftData cleanup tombstone in the same save that removes metadata and transcript segments. File cleanup accepts only the exact `meeting-<UUID>` directory beneath Whisper's Recordings root.
- Failed file cleanup preserves its tombstone and is retried on the next app launch. A missing directory is treated as already cleaned, making retries idempotent.
