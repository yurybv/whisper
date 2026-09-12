# WH-M3-002 Home, Modes, and Settings verification

Date: 2026-09-12. Mac: Apple Silicon, macOS 26.4.1 (25E253).

## Automated evidence

- `xcodegen generate` passed.
- `xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test` passed **199 tests**: 193 unit and 6 UI, with zero failures.
- Result bundle: `/Users/yurybogdanov/Library/Developer/Xcode/DerivedData/Whisper-cvohsozztgjbkycfgedqypyhclkz/Logs/Test/Test-Whisper-2026.09.12_22-42-13-+0400.xcresult`.
- The required build and `codesign --verify --deep --strict` passed for the generated Debug app.
- UI coverage completes onboarding, navigates Home and Settings, verifies the protected Default mode, and creates, edits, activates, duplicates, renames, and deletes a custom mode. Existing mode-switcher tests cover search, keyboard activation, and closure.
- Unit coverage includes settings persistence, partial-shortcut recovery, shortcut chord capture, conflict handling, live API-key state, safe Keychain failures, stale connection-test invalidation, Home readiness, five-item merged history, active-mode fallback, persistence failures, and focused-target capture.
- Focused regressions failed before implementation for the new behavior and passed after correction. The final independent read-only review found no remaining blocking or important issue.

## Visual and manual observations

- [Home](home.png) matches the approved native dark shell: five-item sidebar, visible current microphone, readiness and three primary actions, top-aligned two-column status cards, shortcut summary, and recent history below.
- [Modes](modes.png) uses the approved master-detail composition. Default is visibly marked built-in and active; its fields are disabled, while duplication remains available. Automated interaction confirms rename and delete are unavailable for Default and exercises the full custom-mode lifecycle.
- [Settings](settings.png) keeps the saved key masked and groups its actions with connection status. Audio, shortcut, launch, sound, retention, permission, setup, and About controls use native components and remain scrollable at the minimum supported window size.
- Error presentation was inspected in context: Keychain errors stay in the OpenAI card and launch errors stay in Application. Readiness is not color-only, and permission rows include text status and exact repair controls.
- The screenshot fixture uses only in-memory data and a fake key-state flag. It does not read production Keychain, user history, permissions, or the network. No private text, API key, transcript, mode instruction, or Authorization header appears in the evidence.

## Review corrections

- Changed mode rows into separate selectable controls and action menus for valid input and accessibility behavior.
- Made shortcut capture wait through modifier chords, surface model persistence failures safely, and merge incomplete stored shortcut maps with defaults.
- Reloaded main-window mode state after global switcher activation and made Home readiness account for microphone, API-key, Accessibility, and Input Monitoring state.
- Made Keychain reads recoverable, kept errors beside their actions, and prevented stale or replacement-time connection tests from corrupting state.
- Home now hides Whisper and waits for macOS to restore the immediately previous application before the coordinator captures its focused target, avoiding insertion into Whisper itself or a stale application.
- Limited recent-history fetches before mapping and top-aligned unequal Home cards.

## Result

All WH-M3-002 acceptance criteria and required checks pass. `WH-M3-003` is unblocked for the dedicated keyboard, VoiceOver, focus, and state audit.
