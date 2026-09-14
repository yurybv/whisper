# WH-M4-005 Recordings verification

Date: 2026-09-15. Mac: Apple Silicon, macOS 26.4.1.

## Automated evidence

- `xcodegen generate` passed.
- **72 focused tests** across `RecordingsModelTests`, `OverlayLifecycleTests`, `MeetingProcessingCoordinatorTests`, `HotkeyStateMachineTests`, `MenuBarModelTests`, and `SettingsModelTests` cover persistent configuration, start/stop/cancel, retryable stop failure, exact 2 GB blocking, permission recovery, timer and meter updates, nonactivating HUD placement, durable cancellation, processing-state publication, menu-bar timer presentation, and meeting-versus-dictation exclusion.
- `xcodebuild ... build-for-testing` compiled both the unit and UI test targets without launching an application or moving input focus.
- The required Debug app build and `git diff --check` passed during task verification.
- Tests use isolated defaults, protocol fakes, and local synthetic data. They do not read the production Keychain or history and do not send audio, instructions, transcripts, keys, or network requests to OpenAI.

## Screenshot comparison

- [Idle](idle.png) shows the approved Recordings header, prominent Start Recording action, `00:00:00` timer, enabled system-audio and microphone sources, selected microphone, meeting shortcut, three-hour limit, processing instructions, result-language control, and local-audio privacy explanation.
- [Active at 00:37:18](active.png) shows the approved red recording state, live microphone and system meters, Cancel and Stop Recording actions, and configuration locked for the current capture.
- Both images were produced by the offscreen SwiftUI snapshot test at `1040 × 800` points from generic in-memory fixtures, visually inspected, and retained without private user content.

## State and interaction checks

- The production `AppRuntime` owns one `RecordingsModel`, so closing and recreating the main window does not reset the active capture state. The menu item, global Record Meeting shortcut, main-window action, and HUD Stop action all route through that same model and coordinator.
- Start snapshots the selected microphone, trimmed processing instructions, and result language. Stop immediately exposes Finalizing while the coordinator persists capture and subsequent transcription/processing states. A failed stop returns to Recording so the action remains retryable.
- Cancel invokes the coordinator's first-terminal-wins cancellation path, removes the local meeting record only after recorder cancellation, and returns the UI to Idle. Source/capture and processing failures retain an explicit failed state and message.
- Disk availability below 2 GB disables Start and an attempted shortcut action reports the exact threshold. Missing microphone or Screen Recording access disables Start and exposes the corresponding System Settings recovery control. These issues stay inside the Recordings screen until the owner attempts recording.
- While a meeting is recording, the global hotkey state suppresses push-to-talk; attempting dictation reports that the meeting must stop first. Starting a meeting is likewise rejected while dictation is active.
- Independent review first reproduced two cross-feature/state races. The final implementation reserves dictation or meeting start before either path's first suspension, synchronously projects successful dictation state before releasing the reservation, queries the coordinator for authoritative active capture state, and ignores foreign meeting IDs while recording or finalizing. Re-review passed with no Critical or Important findings.

The owner explicitly requested that development not control the cursor or interrupt foreground work. Therefore live XCUITest launch and physical start/stop/cancel clicks were not applicable in this task run. The UI test target was compiled, the same states/actions were exercised directly through the model and coordinator, and the approved compositions were checked through offscreen screenshots. No cursor automation or permission changes occurred.
