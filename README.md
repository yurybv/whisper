# Whisper

Personal macOS menu-bar dictation MVP. Requires Apple Silicon, macOS 15+, Xcode and XcodeGen. The supported development Mac runs macOS 26.4.1.

```bash
./scripts/bootstrap.sh
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' build
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test
```

To create the local Apple Silicon Release bundle without launching it:

```bash
./scripts/package.sh
```

The script validates arm64, Xcode 26.6+, and the macOS 15+ SDK; regenerates the project; performs a clean Release build; and writes an ad-hoc signed, strictly verified bundle to `build/Whisper.app`. `./scripts/package-local.sh` is a compatibility alias. Developer ID signing, notarization, and installation are intentionally separate from this personal-build step.

On first launch, setup explains the OpenAI data boundary, offers an explicit **Save and Test** key action, and shows Microphone, Screen Recording, Accessibility, and Input Monitoring states across four steps. The saved key is held in Keychain and may be cached in memory for the app session. Opening setup does not read or reveal the saved key, and only pressing **Save and Test** tests the connection.

Continue or close setup to explore the main window without granting permissions. Missing microphone access routes dictation to its repair page. Screen Recording does not block dictation; without Accessibility, use the menu bar and paste results manually. After changing permissions in System Settings, return to Whisper to refresh their status. Use **Relaunch Whisper** if macOS asks you to reopen after a Screen Recording change.

The fourth setup step includes Input Monitoring for global shortcuts alongside Accessibility for shortcut handling and text insertion. Mode and meeting shortcuts are consumed so they do not also trigger the foreground app’s commands. If keyboard monitoring is unavailable, the menu bar reports the exact repair path and retries when you return to Whisper. An enabled Accessibility or Input Monitoring entry can refer to an earlier ad-hoc build; if the current build still lacks access, remove only Whisper’s stale entry and add the current app bundle again.

After setup, **Settings → Preview Setup** reopens the flow without clearing completion; **Reset Setup** clears completion without deleting the key or changing macOS permissions. Completing setup opens Home. The five-item native shell includes functional Home, Modes, Recordings, History, and Settings screens with persistent custom modes, device and shortcut preferences, service status, permissions, recording controls, and unified local history. The meeting pipeline writes microphone and Mac system audio to separate durable tracks, exports and uploads resumable size-bounded chunks, merges diarized chunks into a chronological You/Others transcript, and recovers processing after relaunch without deleting source audio. Recordings exposes the live timer and meters, a nonactivating HUD, persistent processing preferences, permission and low-disk recovery, and one shared Start/Stop path for the window, menu bar, and Command-Shift-R. History provides date groups, type filters, local search, dictation original/result details, recording Transcript/Result details, validated source or mixed playback, Retry/Reprocess actions, result copy, plain-text export, and confirmed deletion with retryable owned-audio cleanup. Audio retention defaults to Forever.

Automated onboarding, main-window, mode CRUD, and mode-switcher UI tests use DEBUG-only `--ui-testing` fixtures, without Keychain, user databases, permission prompts or OpenAI requests. Unit tests use protocol fakes. The scheme includes both unit and UI targets.

Task status and verification evidence: [local backlog](docs/implementation/task-backlog.md), [onboarding QA](docs/testing/evidence/WH-M3-001/qa.md), [main UI QA](docs/testing/evidence/WH-M3-002/qa.md), [accessibility QA](docs/testing/evidence/WH-M3-003/qa.md), [Recordings QA](docs/testing/evidence/WH-M4-005/qa.md), [History QA](docs/testing/evidence/WH-M5-001/qa.md), [History actions QA](docs/testing/evidence/WH-M5-002/qa.md), [History recovery QA](docs/testing/evidence/WH-M5-003/qa.md), [Packaging QA](docs/testing/evidence/WH-M6-001/qa.md), [Milestone 4 review](docs/implementation/reviews/m4-review.md), [Milestone 5 review](docs/implementation/reviews/m5-review.md), [test strategy](docs/testing/test-strategy.md).
