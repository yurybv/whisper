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


## Live grants and shortcut recovery correction — 2026-09-07

The owner explicitly approved Microphone, Screen Recording, and Accessibility grants for the reviewed Debug build.

- Microphone moved from Not Requested to Granted after Request Access. Screen Recording moved from Not Granted to Granted after enabling Whisper in System Settings and reopening.
- Accessibility initially remained Not Granted despite its enabled Settings row, even after toggling and restarting. Replacing the stale row with the exact current DerivedData app bundle made the live application report Granted. This matches the ad-hoc identity issue documented in the milestone 2 review.
- All three permission pages and the final summary reported Granted. Completing setup opened Home. Settings reflected each grant and Preview Setup worked without clearing completion.
- The Screen Recording repair link followed by Preview Setup retained Relaunch Whisper after permission was granted. The app’s Relaunch button terminated its process and started a new one; onboarding completion persisted, so the menu-bar process did not reopen setup automatically.
- Command–Shift–K sent through computer use did not open the switcher. Read-only `CGGetEventTapList` inspection found the app’s native tap disabled with only the flagsChanged mask (4096), both before and after relaunch. Input Monitoring contained another enabled stale Whisper entry. Its removal was authenticated by the owner during repair; restoration of the current bundle is pending the explicit Input Monitoring decision. No live keyboard-recovery pass is claimed.
- One unrelated Accessibility toggle changed during coordinate targeting and was restored to its original off state. Subsequent list selection used keyboard navigation and checked the selected row before removal. No credentials were read, entered, or saved by the agent.

The correction stays within permission failure/recovery:

- Preflight Input Monitoring before installing a tap and reject a disabled tap after startup.
- Recheck source startup on every refresh while retaining the existing AsyncStream consumer, so native recovery is not bypassed or cancelled.
- Keep shortcut permission failures visible through idle/completed dictation state updates while preserving manual-paste feedback and allowing menu-bar dictation.
- Report the specific Input Monitoring repair path instead of incorrectly directing every failure only to Accessibility.

Verification:

- The source-refresh regression failed first: expected two source start checks, observed one. The listening-access and status-projection tests failed on missing interfaces before their implementation.
- Full scheme passed: **155 unit tests and 4 UI tests**, zero failures (`Test-Whisper-2026.09.07_22-10-28-+0400.xcresult`). A subsequently added successful → denied → recovered listener test also passed with all **5 GlobalHotkeyMonitor tests** (`Test-Whisper-2026.09.07_22-11-54-+0400.xcresult`).
- Tests and build used `/tmp/whisper-recovery-tests` as DerivedData, preserving the previously reviewed app bundle. Required build and `git diff --check` passed.
- Independent read-only code review found no blocking defect. The recommended failed-refresh regression was added. A preexisting delayed native-thread startup race after timeout was noted, without expanding this correction.

Task remains **review**. Pending: owner direction on Input Monitoring status/repair inside the existing fourth setup step, restoring the current build’s Input Monitoring access, and live shortcut recovery for the corrected build. WH-M3-002 remains blocked.


## Approved Input Monitoring setup and restored grant — 2026-09-07

The owner explicitly approved enabling Input Monitoring for the corrected build and adding its status/repair to setup.

- Added Input Monitoring to the native permission snapshot, preflight, request, and exact `Privacy_ListenEvent` Settings route. It shares the existing fourth Accessibility step and participates in readiness, final verification rows, and Settings permission rows.
- The fourth step scrolls independently of Back/Continue. Both request and Settings paths offer relaunch guidance, including after a grant. Missing Input Monitoring leaves menu-bar dictation available.
- Full verification passed: **158 unit tests, 4 UI tests**, zero failures. Result: `/tmp/whisper-recovery-tests/Logs/Test/Test-Whisper-2026.09.07_22-34-50-+0400.xcresult`. Required build, ad-hoc signature verification, and `git diff --check` passed.
- TDD: the new permission/readiness tests failed on the missing Input Monitoring cases/properties before implementation. UI checks exposed an off-screen window/activation conflict with the older debug process, then a test trying to click the new repair control before scrolling it into view. The old idle process was stopped; the final UI test explicitly scrolls to repair and verifies relaunch is hittable at minimum window size.
- Independent read-only review found no blocking issue; its requested request-only relaunch regression was added.
- Granted Input Monitoring through System Settings to the exact final QA bundle `/tmp/whisper-recovery-tests/Build/Products/Debug/Whisper.app`, after the final build and signature verification. The row is enabled. No other permissions were changed during this final grant.
- Launched that bundle (process 9751). Read-only `CGGetEventTapList` inspection confirmed **enabled=true, events=7168** (key-down, key-up, flagsChanged), compared with the prior disabled, modifier-only tap. This is live native-listener evidence, not a claim that a physical shortcut passed.
- Computer-use Command–Shift–K injection into System Settings did not produce a visible Whisper switcher. The owner was asked to press the physical shortcut and open Whisper’s main window. The menu-bar-only app cannot currently be inspected by the window-based computer-use tool until a window is open.

Current status remains **review** pending that final physical shortcut/main-window check. No subsequent task has started. Test recordings that include other desktop windows remain outside the repository; no private screenshots, keys, or dictated text were committed.
