# WH-M5-003 Recovery and failure verification

Date: 2026-09-15. Mac: Apple Silicon, macOS 26.4.1.

## Automated evidence

- The 66-test failure/recovery suite covers network and API-key failures, interrupted and partial capture, relaunch resumption, missing chunk exports, corrupted and missing playback sources, retry/reprocess idempotency, durable cleanup retry, and filesystem containment.
- A corrupted existing single-track M4A is rejected before playback becomes active; a missing source is omitted, and an available sibling track remains playable.
- The complete unit/service suite passed **293 of 293** tests with no failures. Tests use temporary files and protocol fakes and send no audio, transcript, instruction, API key, or authorization data over the network.

## Service-level retry/reprocess smoke

- A synthetic meeting failed transcription with an offline error, retained its captured source paths, and exposed Retry.
- Retry completed transcription once. Two explicit Reprocess operations reused that one preserved transcript and replaced the result rather than duplicating segments or output.
- History actions remained scoped to the selected recording, stopped playback before recovery, reloaded durable state, and surfaced success or safe generic failure text.

Live app and XCUITest interaction was intentionally omitted under the owner's no-cursor instruction. No application window, system permission prompt, user history, Keychain value, or production audio was accessed.
