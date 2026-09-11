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


## Physical shortcut failure and command propagation correction — 2026-09-08

- The owner physically pressed Command–Shift–K and reported Finder Network opening instead of Whisper. This is a failed check, superseding the pending report above.
- Two debug processes were running: the previous QA bundle had an enabled mask-7168 tap; the older DerivedData app had a disabled mask-4096 tap. Secure keyboard input was off. Those observations did not prove action delivery or visible panel presentation.
- Source inspection identified a definite propagation defect: `.listenOnly` cannot consume keyboard events and the callback always returned the original event. Apple documents Command–Shift–K as Finder Network and passive taps as unable to divert events. The foreground action may also affect the switcher’s activation, but that part remains a live hypothesis until retested.
- Changed to an active tap, returning nil only for configured nonmodifier mode/meeting commands and their repeats/releases. Normalized events still reach the actor-owned action state machine. Ordinary keys, modifier-only dictation and context-dependent Escape pass through. Native matching follows initial, changed and reset shortcuts.
- Input Monitoring and Accessibility are preflighted before creating the active tap; denied Accessibility gets its specific repair path. No new permission category is introduced.
- TDD first reproduced passive-tap and missing-consumption failures. Further failing regressions covered configuration updates and Accessibility failure classification. Independent review found unmatched-repeat and missed-release edge cases; failing tests reproduced both before correction. Fresh presses reconcile stale claims, and stop clears them.
- Full scheme passed **168 unit tests and 4 UI tests**, zero failures: `/tmp/whisper-shortcut-fix/Logs/Test/Test-Whisper-2026.09.08_00-49-16-+0400.xcresult`. The reviewer’s final cleanup assertion also passed with all **13 CGEventHotkeyMonitor tests**. Required final build, `codesign --verify --deep --strict`, and `git diff --check` passed. Test events are constructed in process and never posted to the desktop.
- Final QA bundle: `/tmp/whisper-shortcut-fix/Build/Products/Debug/Whisper.app`. Both older debug processes had no open WAV/M4A files and were stopped for the controlled retest. System Settings requests owner authentication before adding the final build to the already-approved Accessibility list. No password or credential is read or entered by the agent.
- Task remains **review**. Refresh Accessibility and Input Monitoring for this final bundle, launch it, then verify the physical shortcut, absence of Finder Network, Escape focus restoration, and final setup status. No next task is eligible until that passes.

## Final-bundle permission refresh — 2026-09-11

- Recovered a clean `master` at `65c4b8f`, matching `origin/master`, with GitHub CLI account `yurybv` and the required HTTPS remote.
- Rebuilt the published commit once at `/tmp/whisper-shortcut-fix/Build/Products/Debug/Whisper.app`. The build succeeded, `codesign --verify --deep --strict` passed, and the bundle identifier is `dev.yury.whisper`.
- Removed only Whisper's stale Input Monitoring and Accessibility entries, added that exact final bundle, and verified both switches are on. No unrelated permission entry was changed.
- After relaunch, setup reports Accessibility **Granted** and Input Monitoring **Granted**. Native `CGGetEventTapList` diagnostics report `enabled=true`, keyboard mask `7168`, and active-filter options `0` for the final process.
- Setup also reports Microphone **Not Requested** and Screen Recording **Not Granted** for this ad-hoc identity. The missing states remain visible and setup remains usable; the real grant, repair-link, relaunch, and completed-setup paths for those permissions were already exercised on 2026-09-07.
- The persisted onboarding-completion flag was restored after temporarily exposing the live setup window. No API key was read, entered, logged, or tested.
- Computer-use Command–Shift–K again opened Finder Network because target-directed synthetic input bypasses the session event tap. This does not contradict the enabled native tap and cannot count as physical shortcut acceptance.

Task remains **review**. The only remaining check is a physical Command–Shift–K from Finder, followed by Escape, confirming the switcher opens, Finder does not handle Network, and focus returns to Finder.

## Built-in display placement correction — 2026-09-11

- Physical shortcut tracing reached every expected layer: the active `CGEventHotkeyMonitor` matched and consumed key code 40 with Command and Shift, `GlobalHotkeyMonitor` published the action, `HotkeyActionRouter` handled `.changeMode`, and `AppRuntime.showModeSwitcher()` ran. This ruled out shortcut delivery as the cause of the invisible switcher.
- Live AppKit inspection showed the panel was positioned while its deferred frame and hosted view still had zero size. SwiftUI later realized it as `560×452`, leaving the original centering calculation stale.
- The panel now selects the Mac's built-in `NSScreen` with `CGDisplayIsBuiltin`, falls back to the main or first screen only when no built-in display is reported, applies its configured content size before activation, and recenters after the hosted view's final layout.
- TDD: the frame-helper test first failed to compile because the helper did not exist. The pre-presentation placement regression then exposed the zero-size frame and verifies the configured `560×420` content frame before ordering the window.
- Focused `OverlayLifecycleTests` passed all 9 tests. After stale test runners were stopped, the complete scheme passed **170 unit tests and 4 UI tests**, zero failures: `/tmp/whisper-shortcut-fix/Logs/Test/Test-Whisper-2026.09.11_23-46-00-+0400.xcresult`.
- Final smoke bundle: `/tmp/whisper-shortcut-fix/Build/Products/Debug/Whisper.app`, identifier `dev.yury.whisper`, ad-hoc signature verified with `codesign --verify --deep --strict`.
- The built-in display has AppKit visible frame `(0, 0, 1728, 1084)` and Core Graphics display height `1117`. With the external `3360×1890` display connected, the smoke switcher appeared at Quartz bounds `(584, 349, 560, 452)`, exactly corresponding to the center of the built-in visible frame.
- No shortcut input, key, dictated text, transcript, instruction, or authorization header was logged or added to repository fixtures.

## Final bundle permission and focus QA — 2026-09-12

- Removed only Whisper's stale Accessibility and Input Monitoring records and added `/tmp/whisper-shortcut-fix/Build/Products/Debug/Whisper.app` to both lists. Both switches report on.
- The normal final process created an enabled active event tap with keyboard mask `7168` and options `0`.
- A background UI smoke kept Finder as the previously active application, presented the switcher at `(584, 349, 560, 452)` on the built-in display, then activated Whisper for keyboard delivery. Escape closed the switcher and restored Finder as the frontmost application.
- System Events and a separate `CGEventPost(.cghidEventTap)` helper both bypassed the app's session tap and went to Finder. They are recorded as diagnostic failures and are not treated as substitutes for physical keyboard input.

Task remains **review**. With the corrected, permission-ready bundle running and Finder frontmost, physically press Command–Shift–K and confirm the centered switcher appears without Finder handling the command. The direct Escape and focus-restoration path already passes, but may be repeated during that final check.
