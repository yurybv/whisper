# Whisper

Personal macOS menu-bar dictation MVP. Requires Apple Silicon, macOS 15+, Xcode and XcodeGen. The supported development Mac runs macOS 26.4.1.

```bash
./scripts/bootstrap.sh
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' build
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test
```

On first launch, setup explains the OpenAI data boundary, offers an explicit **Save and Test** key action, and shows Microphone, Screen Recording, Accessibility, and Input Monitoring states across four steps. The saved key is held in Keychain and may be cached in memory for the app session. Opening setup does not read or reveal the saved key, and only pressing **Save and Test** tests the connection.

Continue or close setup to explore the main window without granting permissions. Missing microphone access routes dictation to its repair page. Screen Recording does not block dictation; without Accessibility, use the menu bar and paste results manually. After changing permissions in System Settings, return to Whisper to refresh their status. Use **Relaunch Whisper** if macOS asks you to reopen after a Screen Recording change.

The fourth setup step includes Input Monitoring for global shortcuts alongside Accessibility for shortcut handling and text insertion. Mode and meeting shortcuts are consumed so they do not also trigger the foreground app’s commands. If keyboard monitoring is unavailable, the menu bar reports the exact repair path and retries when you return to Whisper. An enabled Accessibility or Input Monitoring entry can refer to an earlier ad-hoc build; if the current build still lacks access, remove only Whisper’s stale entry and add the current app bundle again.

After setup, **Settings → Preview Setup** reopens the flow without clearing completion; **Reset Setup** clears completion without deleting the key or changing macOS permissions. Completing setup opens Home. The five-item native shell includes functional Home, Modes, and Settings screens with persistent custom modes, device and shortcut preferences, service status, permissions, and the five latest local history items. Meeting capture, Recordings content, and full History remain in the local backlog.

Automated onboarding, main-window, mode CRUD, and mode-switcher UI tests use DEBUG-only `--ui-testing` fixtures, without Keychain, user databases, permission prompts or OpenAI requests. Unit tests use protocol fakes. The scheme includes both unit and UI targets.

Task status and verification evidence: [local backlog](docs/implementation/task-backlog.md), [onboarding QA](docs/testing/evidence/WH-M3-001/qa.md), [main UI QA](docs/testing/evidence/WH-M3-002/qa.md), [test strategy](docs/testing/test-strategy.md).
