# Milestone 5 Review

- Date: 2026-09-15
- Milestone: History and retention
- Review task: `WH-M5-004`
- Verdict: **PASS — AUTHORIZE NEXT MILESTONE**

## Decision

Milestone 5 passes its exit gate. Unified local History preserves complete dictation and recording evidence, exposes safe recovery for recoverable meeting states, validates source audio before playback, keeps exports free of hidden metadata, and contains deletion to the selected record and exact UUID-owned recording directory. Milestone 6 is authorized and `WH-M6-001` is ready.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M5-001` | `a2209c9` | Unified snapshots, deterministic grouping/filter/search, full dictation and recording details, explicit empty/error/processing states |
| `WH-M5-002` | `85657ae` | Owned-source playback, result-only copy, privacy-minimized text export, confirmed deletion, durable tombstones, `Forever` retention |
| `WH-M5-003` | `9bfffe6` | History Retry/Reprocess, corrupt-audio validation, relaunch/failure coverage, duplicate-free recovery smoke |

Every listed commit is an ancestor of `origin/master`. No Critical or Important finding remains open.

## History matrix

| State | Visible evidence | Safe action | Review result |
|---|---|---|---|
| Ready dictation | Original text, processed result, mode snapshot, target app when stored | Copy result, export, confirmed delete | PASS |
| Failed dictation | Preserved original/output text and explicit failure | Export and delete; retry remains in the existing dictation recovery surface | PASS |
| Recording/finalizing | Durable row and status | Delete and reprocess disabled while capture owns the item | PASS |
| Captured/transcribing/processing | Source paths, transcript progress, instructions and language snapshot | Startup recovery resumes durable stage; active destructive actions disabled | PASS |
| Retryable network/missing-key failure | Preserved audio/transcript, “Needs Retry”, safe explanation | Retry from recording detail; Reprocess when a transcript exists | PASS |
| Invalid key/non-transient processing failure | Preserved audio/transcript/result and explicit limitation | Reprocess is available only when a transcript exists; no automatic retry | PASS |
| Interrupted/partial capture | Available source path(s), duration and failure explanation | Available sibling track remains playable; preserved evidence can be exported/deleted | PASS |
| Missing/corrupt audio | Transcript/result remain visible | Missing tracks are omitted; corrupt tracks fail before active playback with safe text | PASS |
| Deleted meeting with failed file cleanup | Metadata removal plus durable cleanup tombstone | Idempotent launch retry; only exact `meeting-<UUID>` directory is eligible | PASS |
| Empty/load failure/search miss | Explicit empty, error, Try Again, or no-match presentation | Reload or change query/filter | PASS |

## Safety and privacy findings

- Playback resolves only relative paths owned by the selected meeting, validates audio duration and tracks, aligns mixed sources by persisted offsets, and never modifies originals.
- Plain-text export includes user-visible transcript/result content but excludes storage paths, UUIDs, target bundle IDs, instructions, error metadata, and credentials. Clipboard copy contains only the processed result.
- Meeting deletion removes the selected SwiftData row and segments in the same save that creates a cleanup tombstone. Cleanup rejects traversal, wrong-meeting paths, and symlink redirection; a missing directory is treated as already clean.
- `Forever` remains the only approved MVP retention policy and performs no automatic history deletion. It only retries cleanup explicitly requested by a prior confirmed deletion.
- Source scans found no `print`, `debugPrint`, `os_log`, `Logger`, Authorization header, credential, transcript, or instruction logging path in Milestone 5 runtime code.

## Verification evidence

The reviewed `9bfffe6` tree completed:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" -derivedDataPath /tmp/whisper-m5-003-red test -only-testing:WhisperTests
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" -derivedDataPath /tmp/whisper-m5-003-red test \
  -only-testing:WhisperTests/MeetingProcessingCoordinatorTests \
  -only-testing:WhisperTests/MeetingTranscriberTests \
  -only-testing:WhisperTests/AudioChunkPlannerTests \
  -only-testing:WhisperTests/PersistenceTests \
  -only-testing:WhisperTests/RetentionServiceTests \
  -only-testing:WhisperTests/AudioPlaybackServiceTests \
  -only-testing:WhisperTests/HistorySearchModelTests
codesign --verify --deep --strict /tmp/whisper-m5-003-red/Build/Products/Debug/Whisper.app
./scripts/check-environment.sh
git diff --check
```

Results:

- **293 of 293** unit/service tests passed with zero failures. Result bundle: `/tmp/whisper-m5-003-red/Logs/Test/Test-Whisper-2026.09.15_13-28-01-+0400.xcresult`.
- The focused failure/recovery suite passed **66 of 66** tests, including retry/reprocess, relaunch, missing/corrupt files, partial capture, and cleanup containment.
- UI targets compiled without launch as part of the test build. The Debug app passed strict ad-hoc signature verification.
- The environment check passed on Apple Silicon macOS 26.4.1 with the required permissions and 1.6 TiB available. `git diff --check` and the privacy scan passed.
- Retained populated, empty, and error screenshots were visually inspected. Live XCUITest was intentionally omitted under the owner's no-cursor instruction; service/model tests exercised the action matrix without opening the app.

## Milestone 6 readiness

The local app has stable durable records, contained file ownership, explicit recovery state, and a fully passing unit/service suite. Deterministic ad-hoc packaging can now operate on this reviewed baseline without changing History behavior.

## Authorization

**PASS — AUTHORIZE NEXT MILESTONE.** Milestone 6 may begin with `WH-M6-001` after this review is present on `origin/master`.
