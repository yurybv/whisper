# Milestone 2 Review

- Date: 2026-08-25
- Milestone: End-to-end dictation
- Review task: `WH-M2-007`
- Verdict: **BLOCK NEXT MILESTONE**

## Decision

Milestone 2 is not yet through its exit gate. The implementation has strong deterministic coverage and the macOS app builds, but the mandatory live Default Russian, Default English, and Russian-to-English TextEdit matrix cannot run until the owner's OpenAI key is available through the production Keychain entry. The review also found three recoverable product gaps, now tracked as `WH-M2-008`: failed network work has no explicit retry/discard path, clipboard-only completion is presented as insertion, and user-facing errors do not provide safe recovery guidance.

Milestone 3 remains blocked. Complete `WH-M2-008`, provision the local Keychain credential without committing or sharing it, and resume `WH-M2-007` for the live gate.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M2-001` | `7b523c8` | OpenAI REST transport, bounded multipart upload, response decoding, secret-safe request construction, and bounded retries |
| `WH-M2-002` | `0ae1ecf` | WAV microphone capture, metering, silence detection, cancellation cleanup, and device-loss handling |
| `WH-M2-003` | `516f1a6` | Actor-isolated dictation state machine, mode/target snapshots, transformation, history write, and cancellation guards |
| `WH-M2-004` | `d0996e4` | Focused-target capture, direct Accessibility insertion, paste fallback, and clipboard restoration |
| `WH-M2-005` | `9ae9c94` | Global push-to-talk, mode/meeting/cancel shortcuts, event normalization, and conflict checks |
| `WH-M2-006` | `3e8cea3` | Menu-bar shell, nonactivating HUD, key mode palette, keyboard navigation, and focus restoration |

The owner explicitly removed Slack from the approved compatibility scope during this milestone; `59af632` records that product decision. It is not treated as implementation drift and is not restored by this review.

## Architecture and behavior findings

Strengths:

- Protocol boundaries isolate URL loading, Keychain, microphone capture, persistence, Accessibility, and hotkeys.
- `DictationCoordinator` is actor-isolated, snapshots the active mode and focused target, rejects concurrent sessions, and validates session identity after suspension points.
- `OpenAIClient` centralizes model configuration, reads the Keychain immediately before requests, sets `store: false`, and never includes a real network call in automated tests.
- Retry/backoff, multipart limits, cancellation, silence, clipboard preservation, event normalization, and overlay lifecycle have deterministic tests.

Blocking gaps delegated to `WH-M2-008`:

1. A transcription or transformation failure retains only an audio URL. No production action can retry or discard it, and beginning another dictation silently removes it.
2. `.copiedForManualPaste` is discarded by the coordinator, so the HUD reports `Inserted` instead of `Paste manually`.
3. raw `localizedDescription` output does not provide the approved, secret-safe recovery guidance for missing/invalid keys, offline failures, microphone loss, and insertion failures.

The UI-test target compiles, but the two XCUITests are not in the scheme test action because local UI Automation could not bootstrap the test process. This is an explicit test limitation, not claimed automated coverage; the built app's debug smoke hooks supplied keyboard/focus evidence for this milestone.

## Automated verification

Commands repeated during this review:

```bash
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
./scripts/check-environment.sh
git diff --check 3dde632..HEAD
```

Results:

- 118 unit tests pass with zero failures.
- The application build succeeds.
- The environment check reports the supported Mac, Xcode, microphone hardware, microphone permission, and Screen Recording permission ready.
- Source contains no `print`, `debugPrint`, `dump`, `NSLog`, `os_log`, or `Logger` calls.
- Current and historical credential-pattern scans find no OpenAI credential.
- `git diff --check` is clean.

## Manual evidence

| Flow | Evidence | Result |
|---|---|---|
| Microphone capture | Recorder integration and environment checks; live recorder evidence is delegated to the final end-to-end run | Pending final gate |
| Accessibility insertion | Fixed-marker smoke in TextEdit, Notes, and Safari plus clipboard restoration tests | Pass |
| Push-to-talk event tap | Real session smoke observed one Right Option press and one release | Pass |
| Mode palette | Built-app Computer Use smoke verified search focus, keyboard navigation, Escape, and prior-app restoration | Pass |
| HUD | Built-app smoke verified text-plus-icon Listening presentation without opening a key main window | Pass |
| Default Russian/English and Russian-to-English | Production Keychain item is absent, so no real OpenAI request was attempted | Blocked |

## Privacy and safety

- The production app reads the OpenAI key only from Keychain service `dev.yury.whisper.openai`, account `api-key`.
- The `OPENAI_API_KEY` environment variable is intentionally not a production credential path.
- No credential, dictated text, transcript, custom instruction, audio, Authorization header, or private screenshot was added to the repository or logs.
- The review did not request that the owner paste a key into chat, a command argument, or a tracked file.
- Automated tests use fakes and synthetic content only.

## Blockers and recovery

### Owner credential blocker

- **Failed criterion:** real TextEdit dictation in Default Russian, Default English, and the custom Russian-to-English mode.
- **Evidence:** Keychain service `dev.yury.whisper.openai`, account `api-key`, is absent; `OPENAI_API_KEY` is also absent and is not consumed by `AppRuntime`.
- **Affected tasks:** `WH-M2-007`; every Milestone 3 task remains blocked by the milestone gate.
- **Recommended default:** add the key locally through Keychain Access, never through chat or the repository, then rerun this review.
- **Exact external change:** create a generic-password item named `dev.yury.whisper.openai` with account `api-key` and the owner's valid OpenAI API key as its password.

### Implementation blocker

- **Failed criterion:** approved error recovery and clipboard-only completion behavior.
- **Evidence:** the review findings above and deterministic code inspection.
- **Affected tasks:** `WH-M2-007` and the Milestone 2 exit gate.
- **Recommended default:** complete `WH-M2-008`, then resume this review.
- **Exact repository change:** expose retry/discard for the retained dictation session, preserve insertion outcome in state presentation, centralize recovery-oriented messages, and add regression tests.

## Authorization

**BLOCK NEXT MILESTONE.** Do not select Milestone 3 work until `WH-M2-008` is done, the local credential is provisioned, the real TextEdit language matrix passes, and `WH-M2-007` is updated to `done` on `origin/master`.
