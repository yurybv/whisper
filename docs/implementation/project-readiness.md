# Whisper Project Readiness

- Checked: 2026-08-20
- Result: Ready for `WH-M1-001`
- Target: the owner's Apple Silicon Mac
- Check command: `./scripts/check-environment.sh`

## Readiness summary

The selected Mac satisfies the native build requirements and can start the reproducible application scaffold. XcodeGen was the only missing free tool; it was installed during this check with the working Homebrew installation and verified afterward. No application code or project scaffold was created.

| Area | Requirement | Observed | Result |
|---|---|---|---|
| Hardware | Apple Silicon | `arm64` | Pass |
| macOS | 15 or newer | 26.4.1 (build 25E253) | Pass |
| Xcode | 26.6 or newer | 26.6 (build 17F113) | Pass |
| Xcode setup | First-launch components installed | `xcodebuild -checkFirstLaunchStatus` exits 0 | Pass |
| Swift | 6.3 or newer | 6.3.3 | Pass |
| macOS SDK | 15 or newer | 26.5 | Pass |
| Project generator | XcodeGen available | 2.46.0 | Pass |
| Package manager | Working Homebrew | 6.0.18 at `/usr/local` | Pass |
| Workspace storage | At least 2 GiB available | Approximately 1.7 TiB available | Pass |
| Microphone hardware | At least one AVFoundation input | MacBook Pro Microphone, MAJOR V, and Microsoft Teams Audio | Pass |
| Microphone permission | Preflight granted or repair step known | Granted | Pass |
| Screen capture framework | ScreenCaptureKit importable | Available | Pass |
| Screen Recording permission | Preflight granted or repair step known | Granted | Pass |

## Tool bootstrap

The active shell resolves Homebrew to `/usr/local/bin/brew`. XcodeGen was installed with:

```bash
/usr/local/bin/brew install xcodegen
```

If XcodeGen is removed, `./scripts/check-environment.sh` reports the same deterministic repair command. The implementation bootstrap in `WH-M1-001` may rely on a working `brew` plus `brew install xcodegen`; it must not silently install anything before the user or agent runs that script.

This Mac also contains `/opt/homebrew/bin/brew`, but that older installation currently rejects macOS 26.4.1. The working `/usr/local` Homebrew runs as x86_64 through Rosetta, and its XcodeGen 2.46.0 executable was launched successfully. This is non-blocking because XcodeGen produces architecture-independent project files; the application target remains Apple Silicon.

## Permission-dependent steps

The check uses only preflight APIs and never opens a macOS permission prompt.

- Microphone access is currently granted and the built-in MacBook Pro microphone is visible.
- Screen Recording access is currently granted and ScreenCaptureKit imports with the selected SDK.
- If either permission is revoked, grant it during Whisper onboarding under System Settings → Privacy & Security. A missing permission blocks only the dependent runtime feature, not project generation or compilation.
- Accessibility is not required to scaffold `WH-M1-001`; its status and repair action are implemented and verified in the later permissions task.

## Evidence commands

```bash
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
xcodegen --version
brew --version
df -h .
./scripts/check-environment.sh
```

## Decision

`WH-M1-001` can run on this Mac. There is no environment or permission blocker for generating and building the initial macOS project.
