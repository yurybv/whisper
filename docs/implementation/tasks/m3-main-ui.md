# Milestone 3: Main application experience

## WH-M3-001

- **Title:** Build onboarding and permission recovery
- **Type:** feature
- **Status:** review
- **Priority:** P0
- **Scope:** Implement the four-step first-launch flow for API key, microphone, Screen Recording, Accessibility, verification, and exact repair actions.
- **Out of scope:** Permanent onboarding navigation item, accounts, or cloud sync.
- **Acceptance criteria:** First launch enters onboarding; key test is explicit; each permission reports current state; missing permission disables only dependent features; completion opens Home; setup can be previewed/reset from Settings.
- **Required checks:** Onboarding view-model and UI tests from implementation plan Task 11; permission denial/recovery manual QA.
- **Dependencies:** WH-M2-007.
- **Expected files:** `Sources/UI/Onboarding/**`, UI tests.
- **Source:** implementation plan Task 11 and approved Open Design prototype.
- **Blockers:** Final physical Command–Shift–K verification is pending for the rebuilt bundle. Accessibility and Input Monitoring were refreshed for it, its active event tap is enabled, and direct switcher/Escape QA passes on the Mac display; synthetic global shortcuts bypass the session tap and cannot close the remaining hardware-input check.
- **Implementation (2026-09-06):** Four-step setup and final readiness summary; explicit Keychain save/test; current permission states and exact System Settings repair links; relaunch guidance after Screen Recording requests/repair; persisted completion, Settings preview/reset and Home transition. Runtime shares the session key cache and reattempts hotkey startup after Accessibility changes. Only microphone access gates dictation capture.
- **Verification:** 158 unit tests and 4 UI tests passed with the complete Xcode scheme on 2026-09-07; focused regressions failed before implementation. Independent review found no blocking defect. Fourth-step UI tests verify scrolling, repair, relaunch visibility, and keyboard-permission readiness. See [QA evidence](../../testing/evidence/WH-M3-001/qa.md).
- **Input Monitoring update (2026-09-07):** Owner approved its grant and status/repair within the fourth setup step. Added native preflight/request, exact Settings routing, relaunch guidance, readiness gating, final summary and Settings rows. Menu-bar dictation remains microphone-only.
- **Shortcut correction (2026-09-08):** Use an active tap and synchronously consume configured mode/meeting commands, repeats and matching releases while retaining actor delivery. Propagate shortcut reassignment/defaults; keep ordinary keys and modifier-only dictation unchanged; preflight Accessibility with an exact repair message. Regression tests cover unmatched repeats, missed releases and stop/recovery. Independent review findings were corrected.
- **Latest verification (2026-09-08):** Complete scheme passed 168 unit tests and 4 UI tests. The final strengthened cleanup assertion passed with all 13 native-monitor tests. Final build, signature verification and diff check passed. Native tests construct events without posting them to other applications.
- **Live recovery refresh (2026-09-11):** Rebuilt commit `65c4b8f` at `/tmp/whisper-shortcut-fix/Build/Products/Debug/Whisper.app`, verified its ad-hoc signature, and replaced the stale Input Monitoring and Accessibility entries with this exact bundle. Setup reports both permissions Granted. Native diagnostics report an enabled active tap with mask 7168 and options 0. Microphone reports Not Requested and Screen Recording reports Not Granted, confirming the live missing-permission presentation without blocking setup; their grant/relaunch transitions were already verified on 2026-09-07.
- **Built-in display correction (2026-09-11):** Native tracing proved the physical shortcut reached the event tap, state machine, router, and `showModeSwitcher()`. The remaining defect was panel placement before AppKit resolved the SwiftUI content size. The panel now selects the built-in `NSScreen`, centers its configured size before activation, and recenters after final layout. On the two-display Mac, the final smoke window measured `560×452` at Quartz origin `(584, 349)`, the exact center of the built-in display's visible frame; it did not use the external display. The full scheme passed 170 unit tests and 4 UI tests.
- **Final-bundle display QA (2026-09-12):** Replaced Accessibility and Input Monitoring entries with the exact rebuilt app and confirmed its live active tap (`enabled=true`, mask `7168`, options `0`). A foreground smoke run showed the `560×452` switcher at `(584, 349)` on the built-in display; Escape removed the window and returned focus to Finder. System Events and HID-level synthetic Command–Shift–K events bypassed the app's session tap, so neither is counted as the final hardware-input check.
- **Remaining acceptance (2026-09-12):** With Finder frontmost, physically press Command–Shift–K and verify the switcher opens centered on the Mac display without Finder handling the command. The already-passing Escape smoke may then be repeated physically. Do not mark done or unblock WH-M3-002 before the hardware shortcut passes.

## WH-M3-002

- **Title:** Build Home, Modes, and Settings screens
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Implement the five-item native shell's Home, Modes, and Settings destinations, custom-mode CRUD, API key actions, microphone choice, shortcuts, launch behavior, sound, retention, and permissions.
- **Out of scope:** Recordings and History content; statistics; themes; model library; vocabulary.
- **Acceptance criteria:** Default is visibly nondeletable; unlimited custom modes can be created/duplicated/renamed/activated/deleted; active-mode fallback works; settings reflect service state; Home exposes three primary actions and system readiness.
- **Required checks:** Mode and settings UI tests from implementation plan Task 11; screenshot comparison with approved prototype.
- **Dependencies:** WH-M3-001.
- **Expected files:** `Sources/UI/Home/**`, `Sources/UI/Modes/**`, `Sources/UI/Settings/**`, navigation shell and UI tests.
- **Source:** implementation plan Task 11 and approved Open Design prototype.
- **Blockers:** WH-M3-001.

## WH-M3-003

- **Title:** Verify UI states, keyboard access, and VoiceOver
- **Type:** testing
- **Status:** blocked
- **Priority:** P0
- **Scope:** Add and verify loading, empty, populated, failed, saving, conflict, disabled, and permission states; audit focus order, VoiceOver labels, target size, status announcements, and reduced motion.
- **Out of scope:** Visual redesign and post-MVP localization.
- **Acceptance criteria:** Primary screens are keyboard usable; visible focus is consistent; state is never color-only; controls have meaningful VoiceOver output; long content does not clip at supported window sizes.
- **Required checks:** UI tests plus manual keyboard and VoiceOver checklist; screenshot evidence without secrets.
- **Dependencies:** WH-M3-002.
- **Expected files:** UI tests, accessibility helpers, `docs/testing/evidence/WH-M3-003/**`.
- **Source:** spec UI states and accessibility section.
- **Blockers:** WH-M3-002.

## WH-M3-004

- **Title:** Review main application experience
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Compare implemented shell to the approved prototype, verify mode/settings behavior, permission recovery, accessibility evidence, and readiness for meeting capture.
- **Out of scope:** Meeting feature code.
- **Acceptance criteria:** WH-M3-001..003 are done; no persistent onboarding nav item exists; all five destination routes are stable; Milestone 4 is safe to start.
- **Required checks:** Full tests; visual comparison; keyboard and VoiceOver audit; `git diff --check`.
- **Dependencies:** WH-M3-001, WH-M3-002, WH-M3-003.
- **Expected files:** `docs/implementation/reviews/m3-review.md`, backlog updates.
- **Source:** roadmap Milestone 3.
- **Blockers:** Completion of main UI tasks.
