# Whisper MVP Test Strategy

## Automated layers

- Unit tests: domain invariants, state machines, retry, chunk planning, transcript merge, paths, and settings.
- Service tests: Keychain, permissions, capture, Accessibility insertion, persistence, and OpenAI through protocol fakes.
- UI tests: onboarding, mode editing, navigation, shortcut recording, error recovery, and history details.
- Packaging smoke: generated project builds, tests run, app bundle launches, and ad-hoc signature verifies.

Automated tests must not send audio, transcripts, instructions, API keys, or network requests to OpenAI.

Security regression coverage injects only synthetic private-looking values and verifies that provider error bodies cannot reach localized, debug, reflective, or user-presented error text. Persistence coverage also asserts owner-only permissions for app-owned audio directories and rejects path traversal, cross-meeting paths, symbolic-link roots or redirects, and out-of-root deletion.

## Required quality gates

Every code task runs:

```bash
git diff --check
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" build
```

Run focused tests during TDD. Milestone reviews run the complete available test suite:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test
```

Once `scripts/verify.sh` exists, it becomes the canonical full command.

Run the canonical command from the repository root:

```bash
./scripts/verify.sh
```

It performs clean project generation, privacy-pattern checks, shell validation, build-for-testing, unit and UI tests, Release packaging, and signature verification without contacting OpenAI. `--skip-ui-tests` is available only for explicitly documented noninteractive work where launching UI automation would interfere with the active Mac session; it still compiles the UI-test target and is not a substitute for the final release-gate UI run.

## Manual acceptance matrix

Dictation:

- TextEdit, Notes, Safari, and VS Code;
- Russian and English with Default mode;
- Russian-to-English custom mode;
- silence, cancel, no network, invalid key, revoked microphone, and revoked Accessibility;
- active meeting rejects push-to-talk with a clear message.

Meetings:

- microphone plus system audio saved as separate sources;
- start, stop, cancel, low disk, microphone loss, and screen-capture revocation;
- relaunch during captured, transcribing, and processing states;
- synthetic three-hour input without unbounded memory growth;
- You/Others order, processed result, retry, reprocess, playback, export, and delete.

UI and accessibility:

- keyboard-only navigation and visible focus;
- VoiceOver names, values, selected states, and status announcements;
- no meaning conveyed only by color;
- long Russian and English content;
- missing permissions leave unaffected screens usable;
- HUD does not steal focus from the target application.

Distribution:

- clean build on the supported Mac;
- app moved to Applications;
- first launch through right-click Open after Gatekeeper warning;
- all onboarding permission links open the correct System Settings location;
- API key survives relaunch in Keychain and never appears in logs.

## Evidence

Each completed task records commands run and manual checks in its final commit summary or milestone review. UI-changing tasks keep screenshots under `docs/testing/evidence/<task-id>/` only when they contain no secrets or private transcript data.
