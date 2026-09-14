# Milestone 3 Review

- Date: 2026-09-14
- Milestone: Main application experience
- Review task: `WH-M3-004`
- Verdict: **PASS — AUTHORIZE NEXT MILESTONE**

## Decision

Milestone 3 passes its exit gate. Its product, architecture, privacy, visual, keyboard, and accessibility evidence supports the approved main-application experience. The five-destination shell is present, onboarding is not a persistent destination, the complete scheme passes, and the meeting-capture boundary is ready for the declared Milestone 4 architecture.

Milestone 4 is authorized and `WH-M4-001` is ready.

## Scope reviewed

| Task | Evidence on `origin/master` | Result |
|---|---|---|
| `WH-M3-001` | `f279696`, `ce35d28`, `d21894b`, `65c4b8f`, `0740fd0`, `2ab3323`, `6131dc7` | Four-step onboarding, live permission recovery, keyboard monitoring, and the physical Control-Command-M mode-switcher flow |
| `WH-M3-002` | `2783be2` | Home, Modes, Settings, five-route shell, persistent custom-mode lifecycle, service state, and secret-safe UI fixtures |
| `WH-M3-003` | `ca6fa83` | Deterministic accessibility fixtures, 44-point custom targets, AX semantics, state announcements, long-content coverage, and minimum-window evidence |

Every listed commit is an ancestor of `origin/master`. The review started from local `master` synchronized with `origin/master`; the only starting worktree changes marked `WH-M3-004` in progress.

## Product and visual alignment

- `SidebarDestination` contains exactly Home, Modes, Recordings, History, and Settings. `AppRootView` handles all five routes exhaustively, and onboarding replaces the shell only while setup is presented; there is no persistent onboarding navigation item.
- Home exposes readiness, active mode, microphone, OpenAI state, four permission states, the three approved shortcuts, three primary actions, and the five newest local history items without adding productivity statistics.
- Modes keeps Default built in and nondeletable while custom modes support create, duplicate, rename, activate, enable/disable, language selection, validation, and delete with active-mode fallback.
- Settings keeps the API key masked and groups connection actions, microphone choice, shortcut recording, launch behavior, sound, retention, permission repair, and setup recovery.
- Recordings and History are explicit future-milestone placeholders. This is deliberate scope staging, not an unimplemented Milestone 3 route.
- The saved Home, Modes, and Settings evidence uses the approved near-black surface ladder, hairline borders, compact native controls, restrained semantic colors, keycaps, and a fixed five-item sidebar. Long content and failure/permission states remain readable at the supported minimum window.

The visual comparison uses the secret-free screenshots accepted in `docs/testing/evidence/WH-M3-002/` and `docs/testing/evidence/WH-M3-003/`. The final UI run exercised the approved flows without creating another redundant screenshot set.

## Behavior and accessibility findings

- Permission recovery is localized to dependent features. Missing microphone access blocks dictation, while modes, settings, and history navigation remain available; every permission has explicit state text and an exact System Settings repair action.
- Mode and settings state is isolated behind repositories and services. Automated fixtures use in-memory persistence, defaults, permissions, launch services, and secure storage without production Keychain or network access.
- Sidebar selection, mode selection, built-in/active/disabled state, permission values, current microphone, and changing statuses expose concise accessibility semantics. Important state is never conveyed by color alone.
- Custom navigation and mode-action targets are at least 44 points. The minimum `1120 x 760` content size and long mode content have focused UI coverage.
- The recorded macOS accessibility audit covers action, element detection, parent/child relationships, and sufficient descriptions, with only narrowly documented native SwiftUI exceptions.
- The host's keyboard policy tabs through text-entry controls but excludes buttons unless macOS Keyboard Navigation is enabled. This platform behavior is documented; named actions remain available through the accessibility tree.

## Automated verification

Non-disruptive checks repeated during this review:

```bash
xcodegen generate
xcodebuild -quiet -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test -only-testing:WhisperTests
xcodebuild -quiet -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" build
codesign --verify --deep --strict <DerivedData>/Build/Products/Debug/Whisper.app
git diff --check
```

Results:

- 193 of 193 non-UI tests pass with zero failures.
- Unit result bundle: `/Users/yurybogdanov/Library/Developer/Xcode/DerivedData/Whisper-cvohsozztgjbkycfgedqypyhclkz/Logs/Test/Test-Whisper-2026.09.14_13-15-11-+0400.xcresult`.
- XcodeGen regeneration, the application build, ad-hoc signature verification, and `git diff --check` pass.
- Production and test source contain no `print`, `debugPrint`, `dump`, `NSLog`, `os_log`, or `Logger` calls and no Authorization-header logging. Credential-shaped matches are limited to named synthetic test fixtures; implementation-plan link anchors are regex false positives.

An earlier complete-scheme run exposed two UI-test reliability problems:

- The failure result was inspected at `/Users/yurybogdanov/Library/Developer/Xcode/DerivedData/Whisper-cvohsozztgjbkycfgedqypyhclkz/Logs/Test/Test-Whisper-2026.09.14_12-53-51-+0400.xcresult`; Xcode subsequently pruned that local bundle during later build-for-testing work, so the recorded failure summary below is the retained review evidence.
- 202 of 204 tests passed; 2 UI tests failed.
- `OnboardingUITests.testFirstLaunchCompletesFourStepsAndCanPreviewFromSettings()` recorded a Mattermost window as an interrupting element during input. The flow later failed to reach Ready and XCTest could resolve only the standard Zoom Window control instead of Open Home.
- `ModeSwitcherUITests.testKeyboardNavigationActivatesModeAndClosesPalette()` found the Search modes field but immediately queried the Default row before it appeared; the subsequent keyboard action did not close the palette in that run.
- The mode-switcher tests now wait for the Default row to appear and use XCTest's explicit disappearance wait after Return or Escape. The test class is MainActor-isolated consistently with the other UI suites.
- The final verification complete scheme passed **204 of 204 tests**, with zero failures, expected failures, or skips. Result bundle: `/tmp/whisper-m3-004-final.dV32EP/full.xcresult`.

## Privacy and safety

- The UI never exposes the saved API key; fixtures use unmistakably synthetic values and fake connection results.
- Automated tests make no OpenAI request and do not read production Keychain, permissions, history, transcripts, or custom instructions.
- Saved screenshots contain only isolated fixture data and no key, dictated text, private transcript, Authorization header, or personal content.
- Meeting capture remains outside this milestone, so no source-audio ownership or deletion behavior was changed by the review.

## Milestone 4 readiness

The approved architecture is ready for `WH-M4-001`: ScreenCaptureKit stays behind a protocol, microphone and system audio are separate continuously written tracks, complete capture requires both writers to finalize, partial-source failure preserves the surviving track, and Application Support owns durable audio paths. Existing settings and permission state provide the necessary microphone selection and Screen Recording recovery surface.

The backlog now marks `WH-M4-001` ready; later meeting tasks remain blocked by their declared dependencies.

## Follow-up

- Missing Milestone 3 scope: none.
- Open Milestone 3 blocker: none.
- Next eligible task: `WH-M4-001 — Capture microphone and system audio with ScreenCaptureKit`.
- Later meeting tasks remain blocked until their dependencies are complete.

## Authorization

**PASS — AUTHORIZE NEXT MILESTONE.** Milestone 4 may begin with `WH-M4-001` after this review is present on `origin/master`.
