# Whisper MVP Roadmap

Status: approved implementation sequence for the personal macOS MVP.

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

## Milestone 1: Native foundation

Goal: boot a reproducible SwiftUI macOS app with domain models, persistence, secrets, permissions, and settings foundations.

Deliverables:

- XcodeGen application and test targets;
- mode and shortcut domain rules;
- SwiftData metadata and Application Support paths;
- Keychain, permission, and launch-at-login services.

Exit gate: the app builds, foundation tests pass, and `WH-M1-005` is done.

## Milestone 2: End-to-end dictation

Goal: hold Right Option, dictate, release, transform through the active mode, and insert text into the previous application.

Deliverables:

- OpenAI REST transport and retry policy;
- microphone recording and silence handling;
- dictation state machine and mode transformation;
- focused-target capture and text insertion fallback;
- global shortcuts, menu bar shell, HUD, and mode switcher.

Exit gate: Default and Russian-to-English dictation work in TextEdit and `WH-M2-007` is done.

## Milestone 3: Main application experience

Goal: make the approved interface usable for first launch, modes, configuration, and system status.

Deliverables:

- four-step onboarding;
- Home, Modes, and Settings screens;
- custom-mode CRUD and active-mode behavior;
- keyboard, VoiceOver, focus, empty, error, and permission states.

Exit gate: all non-recording screens pass UI and accessibility QA and `WH-M3-004` is done.

## Milestone 4: Durable meeting recording

Goal: record system audio and microphone for up to three hours, preserve the sources, and produce a resumable You/Others transcript and processed result.

Deliverables:

- ScreenCaptureKit dual-source capture;
- size-bounded audio chunk export;
- chronological transcript merge and overlap removal;
- processing instructions, result language, retry, and relaunch recovery;
- Recordings screen and live recording states.

Exit gate: a synthetic long recording survives processing interruption and `WH-M4-006` is done.

## Milestone 5: History and retention

Goal: expose reliable local history for dictations and recordings without risking source audio.

Deliverables:

- unified searchable and filterable history;
- dictation and recording details;
- playback, copy, text export, reprocess, retry, and confirmed delete;
- retention and cleanup rules.

Exit gate: history lifecycle tests pass and `WH-M5-004` is done.

## Milestone 6: Hardening and local release

Goal: produce an ad-hoc signed personal build with clear installation, permission, recovery, and troubleshooting instructions.

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
