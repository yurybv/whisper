# Whisper

Personal macOS menu-bar dictation MVP. Requires Apple Silicon, macOS 15+, Xcode and XcodeGen. The supported development Mac runs macOS 26.4.1.

```bash
./scripts/bootstrap.sh
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' build
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test
```

On first launch, setup explains the OpenAI data boundary, offers an explicit **Save and Test** key action, and shows Microphone, Screen Recording and Accessibility states. The saved key is held in Keychain and may be cached in memory for the app session. Opening setup does not read or reveal the saved key, and only pressing **Save and Test** tests the connection.

Continue or close setup to explore the main window without granting permissions. Missing microphone access routes dictation to its repair page. Screen Recording does not block dictation; without Accessibility, use the menu bar and paste results manually. After changing permissions in System Settings, return to Whisper to refresh their status. Use **Relaunch Whisper** if macOS asks you to reopen after a Screen Recording change.

After setup, **Settings → Preview Setup** reopens the flow without clearing completion; **Reset Setup** clears completion without deleting the key or changing macOS permissions. Completing setup opens Home. Home and Settings currently provide the setup shell; full main screens, meeting capture and History remain in the local backlog.

Automated onboarding and mode-switcher UI tests use DEBUG-only `--ui-testing` fixtures, without Keychain, user databases, permission prompts or OpenAI requests. Unit tests use protocol fakes. The scheme includes both unit and UI targets.

Task status and verification evidence: [local backlog](docs/implementation/task-backlog.md), [onboarding QA](docs/testing/evidence/WH-M3-001/qa.md), [test strategy](docs/testing/test-strategy.md).
