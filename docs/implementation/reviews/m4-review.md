# Milestone 4 Review

- Date: 2026-09-15
- Milestone: Durable meeting recording
- Review task: `WH-M4-006`
- Verdict: **PASS — AUTHORIZE NEXT MILESTONE**

## Decision

Milestone 4 passes its exit gate. Dual-source capture is durable, long audio is exported in bounded chunks, diarized results merge into a stable You/Others transcript, processing is resumable, retry preserves the original instruction snapshot, and the Recordings UI reflects the complete capture lifecycle. Milestone 5 is authorized and `WH-M5-001` is ready.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M4-001` | `b150536` | Separate continuously written microphone and system-audio tracks, live levels, source-loss preservation, cancellation, duration and disk limits |
| `WH-M4-002` | `f823074` | Deterministic overlapping exports below 20 MB, atomic progress, rebuildable temporary chunks, bounded three-hour processing |
| `WH-M4-003` | `696adb8` | You/Others mapping, timestamp normalization, overlap removal, stable chronological merge, malformed-result rejection |
| `WH-M4-004` | `f2436ec` | Durable processing stages, bounded uploads, retry classification, persisted results, relaunch recovery, stable instructions |
| `WH-M4-005` | `039449c` | Recordings screen, HUD, timer, meters, permission/storage recovery, shared lifecycle state, dictation exclusion |

Every listed task commit is an ancestor of `origin/master`. The milestone review also corrected four cross-task integration defects before authorization: completion monitoring now survives Cancel followed by another recording; activation recovery ignores a capture owned by the running coordinator; retryability is exposed end to end in Recordings; and every production meeting start goes through the same dictation exclusion and pre-suspension arbiter.

## Durability and recovery findings

- ScreenCaptureKit and microphone samples are written continuously into separate local AAC tracks. The recorder does not retain a meeting-length audio buffer in memory.
- Capture completion carries its meeting ID. One persistent listener handles automatic duration/source-loss outcomes across multiple sessions and ignores stale events from an earlier meeting.
- Starting, active, and finalizing meetings owned by the current coordinator are excluded from relaunch-style recovery. Orphaned recording/finalizing rows are still marked interrupted without deleting preserved files.
- Capture metadata reaches durable storage before transcription starts. Network, transient API, and missing-key failures leave source audio and completed transcription chunks intact and expose Retry Processing for the original meeting.
- Invalid credentials and non-transient processing failures remain explicitly non-retryable. Retry and reprocessing use the stored instruction and result-language snapshot rather than current settings.
- Disk space below 2 GB blocks capture; space below 4 GB warns. The recorder stops at three hours and finalizes the available sources.

## Long-input and transcript evidence

The synthetic long-input harness creates a sparse three-hour AVAsset, exports nine deterministic chunks, verifies every exported file remains below 20 MB, reopens the files as playable assets, and observes peak resident-memory growth below 64 MiB. This proves bounded export behavior across a three-hour timeline; it is intentionally not a three-hour continuously populated live recording.

Transcript tests cover source ownership, chunk offsets, exact boundary overlap, cross-source collisions, same-source coalescing, multilingual text, deterministic ordering, malformed timestamps, and malformed API responses. Prior completed results remain available when a later chunk or transformation fails.

## UI and interaction evidence

- The retained offscreen screenshots in `docs/testing/evidence/WH-M4-005/` show the approved idle and active Recordings compositions at `1040 × 800`, including sources, permissions, selected microphone, timer, levels, controls, instructions, language, and local-audio disclosure.
- Home, menu bar, global shortcut, HUD, and the Recordings button share one model and coordinator. Meeting start is rejected while dictation is active, including during a suspended start; meeting capture blocks new dictation.
- Recording state survives main-window closure because the production runtime owns the model independently of the window.
- The owner requested no cursor control during this work. The UI test target was compiled, but live XCUITest and physical click repetition were not run. State and action paths were exercised through unit/service tests and offscreen rendering without launching the app.

## Automated verification

Commands completed during the final review:

```bash
xcodebuild -quiet -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" -derivedDataPath /tmp/whisper-m4-006-final-current CODE_SIGNING_ALLOWED=NO test -only-testing:WhisperTests
xcodebuild -quiet -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" -derivedDataPath /tmp/whisper-m4-006-final CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -quiet -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" -derivedDataPath /tmp/whisper-m4-006-signed build
codesign --verify --deep --strict /tmp/whisper-m4-006-signed/Build/Products/Debug/Whisper.app
./scripts/check-environment.sh
git diff --check
```

Results:

- **265 of 265** unit/service tests passed with zero failures, expected failures, or skips. Result bundle: `/tmp/whisper-m4-006-final-current/Logs/Test/Test-Whisper-2026.09.15_12-32-49-+0400.xcresult`.
- The three-hour synthetic export passed both inside the final suite and as a focused run. Focused result bundle: `/tmp/whisper-m4-review-final/Logs/Test/Test-Whisper-2026.09.15_12-16-09-+0400.xcresult`.
- UI targets compiled without launch; the application build and strict signature verification passed.
- The environment check passed on Apple Silicon macOS 26.4.1 with both required permissions, two microphone inputs, ScreenCaptureKit, Xcode 26.6, and 1.6 TiB free.
- Source scans found no application `print`, `debugPrint`, `dump`, `NSLog`, `os_log`, or `Logger` calls and no credential/transcript/instruction logging path.
- Independent read-only re-review returned PASS with no remaining Critical or Important findings.

## Privacy and safety

Source recordings stay under Application Support. Only temporary chunks are prepared for transcription. Automated tests use local synthetic files, isolated storage, and protocol fakes; they do not read the production Keychain or send user audio, transcripts, instructions, keys, or Authorization headers over the network. Capture or processing failures never delete durable source audio.

## Milestone 5 readiness

History can safely build on stable dictation and meeting snapshots, persisted transcript segments, durable audio-relative paths, explicit statuses, retry stages, and result text. `WH-M5-001` may now replace the History placeholder with the unified list and details; destructive lifecycle behavior remains scoped to `WH-M5-002`.

## Authorization

**PASS — AUTHORIZE NEXT MILESTONE.** Milestone 5 may begin with `WH-M5-001` after this review is present on `origin/master`.
