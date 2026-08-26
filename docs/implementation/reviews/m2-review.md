# Milestone 2 Review

- Date: 2026-08-25
- Milestone: End-to-end dictation
- Review task: `WH-M2-007`
- Verdict: **BLOCK NEXT MILESTONE**

## Decision

Milestone 2 is not yet through its exit gate. The production Keychain credential is present, real OpenAI transcription and transformation pass with synthetic English and Russian audio, deterministic coverage is strong, and the macOS app builds. The mandatory in-app Default Russian, Default English, and Russian-to-English TextEdit matrix is still pending. The recovery findings were resolved by `WH-M2-008`, the live transcription response mismatch by `WH-M2-009`, and repeated Keychain reads within one app launch by `WH-M2-010`.

Milestone 3 remains blocked while `WH-M2-007` completes the real app-to-TextEdit gate.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M2-001` | `7b523c8` | OpenAI REST transport, bounded multipart upload, response decoding, secret-safe request construction, and bounded retries |
| `WH-M2-002` | `0ae1ecf` | WAV microphone capture, metering, silence detection, cancellation cleanup, and device-loss handling |
| `WH-M2-003` | `516f1a6` | Actor-isolated dictation state machine, mode/target snapshots, transformation, history write, and cancellation guards |
| `WH-M2-004` | `d0996e4` | Focused-target capture, direct Accessibility insertion, paste fallback, and clipboard restoration |
| `WH-M2-005` | `9ae9c94` | Global push-to-talk, mode/meeting/cancel shortcuts, event normalization, and conflict checks |
| `WH-M2-006` | `3e8cea3` | Menu-bar shell, nonactivating HUD, key mode palette, keyboard navigation, and focus restoration |
| `WH-M2-008` | `9bbd8b1` | Recoverable dictation sessions, Retry/Discard, and completion/error feedback |
| `WH-M2-009` | `d9a9dd3` | Live `languages[].code` transcription response compatibility |
| `WH-M2-010` | task commit | Process-memory Keychain cache with single-flight access and coherent save/delete behavior |

The owner explicitly removed Slack from the approved compatibility scope during this milestone; `59af632` records that product decision. It is not treated as implementation drift and is not restored by this review.

Live OpenAI QA initially found that successful `gpt-transcribe` responses identify languages with `languages[].code`, while the production DTO required `languages[].language`. `WH-M2-009` added compatible decoding for the live field without removing legacy support. Synthetic English and Russian audio then passed real transcription and both Default and Russian-to-English transformations without logging response values.

## Architecture and behavior findings

Strengths:

- Protocol boundaries isolate URL loading, Keychain, microphone capture, persistence, Accessibility, and hotkeys.
- `DictationCoordinator` is actor-isolated, snapshots the active mode and focused target, rejects concurrent sessions, and validates session identity after suspension points.
- `OpenAIClient` centralizes model configuration, receives a process-scoped secure-store cache backed only by Keychain, sets `store: false`, and never includes a real network call in automated tests.
- Retry/backoff, multipart limits, cancellation, silence, clipboard preservation, event normalization, and overlay lifecycle have deterministic tests.

Recovery gaps resolved by `WH-M2-008`:

1. The coordinator retains the complete failed session and resumes from transcription, transformation, insertion, or history without re-recording or duplicate insertion.
2. The menu exposes explicit Retry/Discard, prevents a new dictation from destroying recoverable work, and serializes recovery actions so rapid input cannot race hotkey state.
3. `.copiedForManualPaste` reaches the HUD and menu presentation as `Paste manually`.
4. Centralized error presentation gives recovery guidance for missing/invalid keys, offline failures, microphone loss, and insertion failures without surfacing provider or private content.

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

- 145 unit tests pass with zero failures.
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
| OpenAI Default Russian/English and Russian-to-English | Synthetic English and Russian WAV files passed real transcription; Default preserved each source language and the custom instruction returned English without Cyrillic | Pass |
| In-app TextEdit matrix | The first synthetic Right Option attempt left the TextEdit marker unchanged; no end-to-end insertion is claimed yet | Pending final gate |

## Privacy and safety

- The production app reads the OpenAI key only from Keychain service `dev.yury.whisper.openai`, account `api-key`, and keeps a successful nonempty read only in process memory for the current launch.
- The `OPENAI_API_KEY` environment variable is intentionally not a production credential path.
- No permissive all-app Keychain ACL is used. An ad-hoc rebuild may still require one authorization because its code requirement changes; stable cross-build access remains signed-release work in Milestone 6.
- No credential, dictated text, transcript, custom instruction, audio, Authorization header, or private screenshot was added to the repository or logs.
- The owner supplied the credential in chat after being asked to use the clipboard. It was not echoed or placed in a command argument, tracked file, or application log; rotation is recommended after this gate because chat exposure cannot be undone.
- Automated suite tests use fakes and synthetic content only. The separate temporary live QA used generated WAV files and was removed after execution.

## Blockers and recovery

### Remaining TextEdit gate

- **Failed criterion:** real TextEdit dictation in Default Russian, Default English, and the custom Russian-to-English mode.
- **Evidence:** Keychain service `dev.yury.whisper.openai`, account `api-key`, is present and the real OpenAI stages pass. The first synthetic Right Option attempt did not change the TextEdit marker, so the app-level microphone/hotkey/insertion path still needs direct evidence.
- **Affected tasks:** `WH-M2-007`; every Milestone 3 task remains blocked by the milestone gate.
- **Recommended default:** diagnose the app-level start path without changing product behavior, then rerun the three TextEdit cases.
- **Exact next check:** observe the built app's hotkey/accessibility state during a real recording, confirm microphone output reaches `DictationCoordinator`, and verify the final text is inserted into the captured TextEdit target.

### Resolved implementation blocker

- **Previous failed criterion:** approved error recovery and clipboard-only completion behavior.
- **Resolution:** `WH-M2-008` implements retained-session Retry/Discard, stage-aware continuation, manual-paste presentation, centralized safe messages, and single-flight recovery actions.
- **Evidence:** coordinator, error-presentation, HUD, menu-model, runtime-action, and microphone device-loss tests pass in the 139-test suite; the application build and independent Critical/Important review pass.
- **Remaining impact:** none beyond the separate TextEdit gate above.

### Resolved Keychain authorization blocker

- **Previous failed criterion:** transcription, transformation, and retry could each read the same Keychain item and repeat macOS authorization within one app launch.
- **Resolution:** `WH-M2-010` adds a thread-safe, process-memory cache around the production Keychain store without using `.env`, UserDefaults, or permissive Keychain ACLs.
- **Evidence:** deterministic tests prove a successful key is read once, concurrent initial callers are single-flight, nil/error/blank values remain retryable, and save/delete keep the cache coherent. The concurrent test fails under a deliberate read-outside-lock mutation and passes with the production implementation.
- **Remaining impact:** ad-hoc rebuilds can still prompt once because their code requirement changes. A persistent signing identity is intentionally deferred to Milestone 6.

## Authorization

**BLOCK NEXT MILESTONE.** Do not select Milestone 3 work until the real in-app TextEdit language matrix passes and `WH-M2-007` is updated to `done` on `origin/master`.
