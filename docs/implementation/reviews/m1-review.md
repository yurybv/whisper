# Milestone 1 Review

- Date: 2026-08-21
- Milestone: Native foundation
- Review task: `WH-M1-005`
- Verdict: **APPROVE NEXT MILESTONE**

## Decision

Milestone 1 satisfies its exit gate. The generated macOS application builds cleanly, the foundation test suite passes, persistence and filesystem ownership boundaries are covered, and the OpenAI key is isolated behind the Keychain-backed `SecureStore` contract. Milestone 2 may start with `WH-M2-001`; independent microphone work in `WH-M2-002` is also dependency-ready.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M1-001` | `66f360c`, `2b05324` | Reproducible XcodeGen app, configuration, entitlements, usage descriptions, design tokens, bootstrap, and smoke tests |
| `WH-M1-002` | `65250af`, `0febbec` | Mode invariants, shortcut values, settings defaults, Codable round trips, and feature errors |
| `WH-M1-003` | `8d39191` | SwiftData entities and repositories, safe Application Support paths, cascade cleanup, and relaunch recovery query |
| `WH-M1-004` | `fbcc0a7` | Keychain lifecycle, permission boundaries, settings actions, and recoverable launch-at-login service |

Every implementation commit is an ancestor of `origin/master`. The review started from a synchronized repository with no unpublished commit.

## Foundation and architecture checks

- `./scripts/bootstrap.sh` regenerates `Whisper.xcodeproj` from the committed manifest.
- The app targets arm64 macOS 15 or newer, uses bundle ID `dev.yury.whisper`, and remains an `LSUIElement` menu-bar utility.
- Mode rules preserve exactly one immutable Default mode and validated, case-insensitively unique custom names.
- SwiftData stores mode, dictation, meeting, and transcript metadata; transcript segments have a required cascading meeting relationship.
- `AppPaths` creates only owned `Recordings` and `Temporary` directories and rejects deletion outside the immediate recordings root.
- A disk-backed persistence test closes and reopens the store before querying incomplete meetings.
- Permission and launch-at-login APIs are isolated behind injectable clients so status tests never display system prompts.
- No OpenAI transport, microphone capture, Accessibility insertion, or product UI was added before its milestone.

## Testing and evidence

Commands repeated during this review:

```bash
./scripts/bootstrap.sh
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" clean build
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test
.agents/skills/whisper-next-task/scripts/project-state.sh
git diff --check
```

The clean build exits successfully. The standard scheme test command runs 34 foundation tests with zero failures across Keychain, launch at login, mode rules, permissions, persistence, shortcuts, and application smoke coverage.

The review found that the generated scheme attempted to execute an empty `WhisperUITests` bundle, which cannot contain an executable. A temporary launch test then confirmed that actual macOS UI testing requires Automation authentication on this Mac. The UI-test target remains scaffolded, but it is excluded from the standard scheme until a later UI task adds real tests and their required permission evidence. This keeps the canonical foundation command deterministic without claiming unimplemented UI coverage.

Manual product-flow QA is not applicable yet: Milestone 1 contains no dictation, capture, insertion, or settings UI. Real Keychain add/replace/read/delete behavior is exercised with an isolated test service and synthetic values.

## Privacy and safety

- The default Keychain item uses generic-password service `dev.yury.whisper.openai`, account `api-key`, and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- The API-key lifecycle is exposed only through `SecureStore`; no API-key field exists in UserDefaults, app settings, or SwiftData.
- Secret-pattern scans find no OpenAI key, environment assignment, or bearer header.
- Source scans find no `print`, `Logger`, `os_log`, `NSLog`, or Authorization logging.
- Tests use synthetic strings, local temporary paths, protocol fakes, and zero OpenAI network requests.
- No dictated text, private transcript, custom instruction, or real credential was introduced by the milestone.

## Blockers and follow-up

- Foundation blocker: none.
- Missing Milestone 1 scope: none.
- Manual owner action required for `WH-M2-001`: none; tests must continue to use fake keys and URL loading protocols.
- UI Automation approval is deferred until a task introduces executable UI tests, no earlier than the menu-bar/UI work.
- Next selected task under the backlog ordering rule: `WH-M2-001 — Build OpenAI REST transport and retry policy`.

## Authorization

**APPROVE NEXT MILESTONE.** Milestone 2 implementation may begin within its declared task dependencies and privacy boundaries.
