# Whisper Local Task Backlog

Task details live in `docs/implementation/tasks/`. This index is the selection surface for autonomous work.

## Status legend

- `done`: verified on `origin/master`
- `review`: awaiting final verification
- `in-progress`: currently selected
- `ready`: safe to start when dependencies are done
- `blocked`: waiting for a named dependency or decision

## Milestone 0: Governance and readiness

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M0-001 | Establish local task workflow and repository guardrails | done | — |
| WH-M0-002 | Record native architecture and tooling decisions | done | WH-M0-001 |
| WH-M0-003 | Verify development environment and project readiness | done | WH-M0-002 |
| WH-M0-004 | Review milestone 0 and authorize foundation | done | WH-M0-001..003 |

## Milestone 1: Native foundation

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M1-001 | Scaffold reproducible macOS application | done | WH-M0-004 |
| WH-M1-002 | Implement mode, shortcut, and settings domain rules | done | WH-M1-001 |
| WH-M1-003 | Add SwiftData persistence and file layout | ready | WH-M1-002 |
| WH-M1-004 | Add Keychain, permissions, and launch-at-login services | ready | WH-M1-001 |
| WH-M1-005 | Review milestone 1 foundation | blocked | WH-M1-001..004 |

## Milestone 2: End-to-end dictation

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M2-001 | Build OpenAI REST transport and retry policy | blocked | WH-M1-005 |
| WH-M2-002 | Build microphone recorder and silence handling | blocked | WH-M1-005 |
| WH-M2-003 | Implement mode transformation and dictation state machine | blocked | WH-M2-001..002 |
| WH-M2-004 | Capture focused target and insert text reliably | blocked | WH-M2-003 |
| WH-M2-005 | Implement global shortcuts and shortcut recorder | blocked | WH-M2-003 |
| WH-M2-006 | Build menu bar shell, HUD, and mode switcher | blocked | WH-M2-003..005 |
| WH-M2-007 | Review end-to-end dictation milestone | blocked | WH-M2-001..006 |

## Milestone 3: Main application experience

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M3-001 | Build onboarding and permission recovery | blocked | WH-M2-007 |
| WH-M3-002 | Build Home, Modes, and Settings screens | blocked | WH-M3-001 |
| WH-M3-003 | Verify UI states, keyboard access, and VoiceOver | blocked | WH-M3-002 |
| WH-M3-004 | Review main application experience | blocked | WH-M3-001..003 |

## Milestone 4: Durable meeting recording

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M4-001 | Capture microphone and system audio with ScreenCaptureKit | blocked | WH-M3-004 |
| WH-M4-002 | Export size-bounded long-audio chunks | blocked | WH-M4-001 |
| WH-M4-003 | Merge diarized chunks into a chronological transcript | blocked | WH-M4-002 |
| WH-M4-004 | Implement processing, retry, and relaunch recovery | blocked | WH-M4-003 |
| WH-M4-005 | Build Recordings screen and recording states | blocked | WH-M4-001..004 |
| WH-M4-006 | Review durable meeting recording milestone | blocked | WH-M4-001..005 |

## Milestone 5: History and retention

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M5-001 | Build unified history list and details | blocked | WH-M4-006 |
| WH-M5-002 | Add playback, export, delete, and retention behavior | blocked | WH-M5-001 |
| WH-M5-003 | Harden failure, retry, and cleanup behavior | blocked | WH-M5-001..002 |
| WH-M5-004 | Review history and retention milestone | blocked | WH-M5-001..003 |

## Milestone 6: Hardening and local release

| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M6-001 | Add deterministic ad-hoc packaging | blocked | WH-M5-004 |
| WH-M6-002 | Add full automated verification command | blocked | WH-M6-001 |
| WH-M6-003 | Run target-app and failure-state acceptance matrix | blocked | WH-M6-002 |
| WH-M6-004 | Complete privacy, security, and logging review | blocked | WH-M6-002 |
| WH-M6-005 | Write installation and operating runbook | blocked | WH-M6-001..004 |
| WH-M6-006 | Review MVP release readiness | blocked | WH-M6-001..005 |

## Selection rule

Select the lowest-numbered `ready` task in the earliest open milestone. A blocked task becomes ready only when every listed dependency is done and the previous milestone review explicitly authorizes the milestone.
