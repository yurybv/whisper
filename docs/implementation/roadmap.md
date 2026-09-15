# Whisper MVP Roadmap

Status: Milestones 0 through 4 complete; Milestone 5 authorized on 2026-09-15.

## Principles

- Build working vertical capabilities, not disconnected UI shells.
- Keep the API key in Keychain and audio under Application Support.
- Write meeting audio continuously to disk before any network processing.
- Keep OpenAI behind protocol boundaries and use fakes in automated tests.
- Protect the default mode, push-to-talk flow, recording recovery, and privacy rules as core invariants.
- Finish each milestone with a review before starting the next.

## Milestone 0: Governance and readiness

Goal: establish the local task workflow, approved technical decisions, and a verified development environment.

Deliverables:

- local task source of truth and agent workflow;
- Xcode/XcodeGen/macOS SDK readiness check;
- architecture decision record for the native personal MVP;
- readiness review with no unresolved foundation blocker.

Exit gate: `WH-M0-004` is done.

Review: passed on 2026-08-20. See [Milestone 0 review](reviews/m0-review.md).

## Milestone 1: Native foundation

Goal: boot a reproducible SwiftUI macOS app with domain models, persistence, secrets, permissions, and settings foundations.

Entry gate: authorized by `WH-M0-004`; begin with `WH-M1-001` only.

Progress: `WH-M1-001` through `WH-M1-005` completed on 2026-08-21.

Review: passed on 2026-08-21. See [Milestone 1 review](reviews/m1-review.md).

Deliverables:

- XcodeGen application and test targets;
- mode and shortcut domain rules;
- SwiftData metadata and Application Support paths;
- Keychain, permission, and launch-at-login services.

Exit gate: the app builds, foundation tests pass, and `WH-M1-005` is done.

## Milestone 2: End-to-end dictation

Goal: hold Right Option, dictate, release, transform through the active mode, and insert text into the previous application.

Entry gate: authorized by `WH-M1-005`; select `WH-M2-001` first under the backlog ordering rule.

Progress: `WH-M2-001` through `WH-M2-010` are complete. The real Default English, Default Russian, and Russian-to-English mode outputs passed the focused TextEdit insertion matrix on 2026-09-05.

Deliverables:

- OpenAI REST transport and retry policy;
- microphone recording and silence handling;
- dictation state machine and mode transformation;
- focused-target capture and text insertion fallback;
- global shortcuts, menu bar shell, HUD, and mode switcher.

Exit gate: passed on 2026-09-05; Default and Russian-to-English dictation work in TextEdit and `WH-M2-007` is done. See [Milestone 2 review](reviews/m2-review.md).

## Milestone 3: Main application experience

Goal: make the approved interface usable for first launch, modes, configuration, and system status.

Entry gate: authorized by `WH-M2-007`; begin with `WH-M3-001`.

Progress: `WH-M3-001` through `WH-M3-004` completed on 2026-09-14. The native five-destination shell includes functional Home, Modes, and Settings screens, persistent custom-mode CRUD, settings/service state, focused-target-safe Home dictation startup, 44-point custom navigation/action targets, explicit non-color-only states, and concise AX semantics. The final complete scheme passed 204 tests with zero failures or skips after stabilizing the mode-switcher disappearance checks. See [Milestone 3 review](reviews/m3-review.md).

Deliverables:

- four-step onboarding;
- Home, Modes, and Settings screens;
- custom-mode CRUD and active-mode behavior;
- keyboard, VoiceOver, focus, empty, error, and permission states.

Exit gate: all non-recording screens pass UI and accessibility QA and `WH-M3-004` is done.

Review: passed on 2026-09-14. `WH-M4-001` is ready.

## Milestone 4: Durable meeting recording

Goal: record system audio and microphone for up to three hours, preserve the sources, and produce a resumable You/Others transcript and processed result.

Progress: `WH-M4-001` through `WH-M4-006` completed by 2026-09-15. ScreenCaptureKit writes selected-microphone and system audio continuously to separate durable mono AAC files, preserves their shared-timeline offsets, publishes meters and automatic terminal outcomes, and safely handles source loss, low disk, cancellation, and concurrent lifecycle commands. Durable source tracks export sequentially into deterministic 20-minute M4A chunks with one-second overlap; oversized ranges split recursively below 20 MB, and atomic manifests/results resume progress or rebuild missing temporary exports without losing completed transcription state. Diarized results map deterministically to You/Others and merge chronologically. The production runtime resumes incomplete processing with stable instruction snapshots, owner-correlated completion events, bounded concurrent uploads, and explicit retry actions while preserving all captured audio. The Recordings destination, nonactivating HUD, menu bar, and Command-Shift-R share durable Start/Stop/Cancel state, live timer and meters, saved processing preferences, exact permission/storage recovery, and dictation exclusion. See [Milestone 4 review](reviews/m4-review.md).

Deliverables:

- ScreenCaptureKit dual-source capture;
- size-bounded audio chunk export;
- chronological transcript merge and overlap removal;
- processing instructions, result language, retry, and relaunch recovery;
- Recordings screen and live recording states.

Exit gate: a synthetic long recording survives processing interruption and `WH-M4-006` is done.

Review: passed on 2026-09-15. `WH-M5-001` is ready.

## Milestone 5: History and retention

Goal: expose reliable local history for dictations and recordings without risking source audio.

Progress: `WH-M5-001` through `WH-M5-004` completed on 2026-09-15. History combines full local dictation and recording snapshots with transcript segments, deterministic date grouping, type filters, case-insensitive search, explicit status/error states, and details for original/processed dictation text and recording Transcript/Result content. Details support validated owned-source playback, Retry/Reprocess without duplicate durable output, result-only copy, privacy-minimized text export, and confirmed deletion through idempotent cleanup tombstones. Missing, corrupt, partial-track, interrupted, and relaunch states preserve available evidence and expose safe recovery where applicable. The approved `Forever` policy performs no automatic history deletion. The milestone review passed and authorized Milestone 6.

Deliverables:

- unified searchable and filterable history;
- dictation and recording details;
- playback, copy, text export, reprocess, retry, and confirmed delete;
- retention and cleanup rules.

Exit gate: history lifecycle tests pass and `WH-M5-004` is done.

Review: passed on 2026-09-15. `WH-M6-001` is ready.

## Milestone 6: Hardening and local release

Goal: produce an ad-hoc signed personal build with clear installation, permission, recovery, and troubleshooting instructions.

Progress: `WH-M6-001` completed on 2026-09-15. The canonical packaging script produces a clean, deterministic-path, arm64-only Release bundle at `build/Whisper.app`, applies a timestamp-free ad-hoc signature, and verifies the result. Unsupported architecture, Xcode, and SDK versions fail before generation or build. `WH-M6-002` is ready to compose the full automated verification command.

Deliverables:

- deterministic packaging script;
- full automated test command;
- manual acceptance matrix across target apps and failure states;
- privacy and logging review;
- installation and operating runbook.

Exit gate: the packaged app passes the acceptance matrix and `WH-M6-006` is done.

## Explicit post-MVP work

Do not add these items to the active MVP backlog without an owner request:

- notarization, App Store distribution, or automatic updates;
- accounts, subscriptions, analytics, or cloud sync;
- local speech models or multiple providers;
- individual remote-speaker identification;
- mobile, Windows, Linux, or Intel Mac support;
- vocabulary management, productivity statistics, or app-specific mode activation.
