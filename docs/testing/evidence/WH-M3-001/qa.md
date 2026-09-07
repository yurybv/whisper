# WH-M3-001 onboarding verification

Date: 2026-09-06. Mac: Apple Silicon, macOS 26.4.1 (25E253). Starting commit: `1c7b65f`. Task remains **review**, pending live permission recovery.

## Automated evidence

- `xcodegen generate` passed.
- `xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' build` passed; `git diff --check` passed.
- `xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test` passed: **151 unit tests, 4 UI tests**, zero failures.
- Result bundle: `Test-Whisper-2026.09.06_18-50-41-+0400.xcresult` in the local Xcode DerivedData test logs.
- Onboarding: six model tests cover explicit testing, secret-safe failure output, saved-key masking, preview/reset/completion, live snapshot refresh, exact recovery routing, microphone-only dictation gating and relaunch guidance after granting Screen Recording. Two UI tests cover full setup and Settings preview, invalid key, denied permissions, limited completion, and Ready-page Screen Recording repair.
- TDD: initial UI tests failed because setup did not exist; model tests first failed on the missing model. The screen-request relaunch regression failed on its behavioral assertion before correction. UI testing also caught preview returning to Home instead of Settings.
- The canonical scheme previously omitted WhisperUITests. It now runs both targets. Mode-switcher UI fixtures use `--ui-testing`, in-memory mode data and no production runtime. Their panel stays discoverable while XCTest activates its runner; the real panel configuration is unchanged. The Default row assertion uses its actual accessibility button role.
- No automated test requests permissions or sends data to OpenAI. No real key was entered or read during manual QA.

## Manual observations

Using the built Debug app under Xcode DerivedData (not a separately installed app):

- First launch opens setup with an empty secure field and no automatic connection request.
- The four steps show progress, Back/Continue, explanatory text, and current permission status. The dark layout was visually inspected at the supported window size; no clipping was observed on the microphone page.
- Microphone shows **Not Requested**. Its repair button opens **System Settings → Privacy & Security → Microphone**.
- Screen Recording shows **Not Granted**. Its repair button opens **Screen & System Audio Recording**. Returning to Whisper exposes **Relaunch Whisper** and conditional macOS guidance.
- Accessibility shows **Not Granted**. Its repair button opens **System Settings → Privacy & Security → Accessibility**.
- System Settings already contains enabled Whisper Microphone and Accessibility entries, but the live build still reports unavailable access. No assumption was made that those entries authorize this binary.
- No permission switch was changed and no real API request was made.

## Review

Independent read-only review found a missing relaunch action after Request Access or Ready-page repair. The model now tracks both paths, and guidance is visible even after the permission becomes granted and on the final summary. Model/UI regressions cover the change. User-facing milestone/task jargon was removed.

## Remaining blocker and exact next action

Live grant/recovery QA is incomplete. The current build needs Microphone, Screen Recording and Accessibility access to verify the real macOS transitions, hotkey recovery after returning from Settings, and relaunch behavior. Computer-use policy requires confirmation at action time before granting an app security-sensitive access. Ask the owner to authorize these permissions for the reviewed build, or have the owner grant them directly.

Once authorized: request/grant each permission, verify the live state after returning; use Relaunch if requested by macOS; verify Accessibility restores shortcut monitoring and microphone denial routes dictation to repair. Preserve existing user permission entries. Update this record, complete WH-M3-001, unblock WH-M3-002 and push the completion commit after repository guards pass. No next task is eligible before then.

## Recovery verification — 2026-09-07

- Recovered a clean `master` at `f279696`; after fetching, local and `origin/master` matched. Account `yurybv`, expected HTTPS remote, and task-status consistency checks passed. There were no unpublished commits or other active tasks.
- Reran the complete Xcode scheme: **151 unit tests and 4 UI tests passed**, zero failures. Result bundle: `Test-Whisper-2026.09.07_21-48-22-+0400.xcresult` in Xcode DerivedData test logs.
- The required `xcodebuild ... build` and `git diff --check` passed.
- Inspected the live Whisper setup before running UI tests: the API-key page had an empty secure field and no test request; Continue opened Microphone access, still reporting **Not Requested**. No permission was requested or changed and no API key was read or entered.
- Reviewed the permission service, onboarding model/view, runtime refresh, relaunch implementation, and existing onboarding tests. The remaining live recovery criterion still requires permission grants; automated fixtures do not satisfy it. Requested owner authorization under the computer-use tool's security-sensitive-access confirmation policy.
- Task remains **review**; no implementation task was completed and WH-M3-002 remains blocked.
