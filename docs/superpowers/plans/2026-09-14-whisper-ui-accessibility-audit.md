# Whisper Main UI Accessibility Audit Implementation Plan

> **For Codex:** Use the executing-plans skill to implement this plan one task at a time. Keep verification focused here; the complete scheme belongs to the immediately following Milestone 3 review.

**Goal:** Make Home, Modes, and Settings keyboard- and VoiceOver-friendly, prove the supported UI states are explicit and non-color-only, and retain secret-free audit evidence.

**Architecture:** Preserve the current SwiftUI screen and model structure. Add accessibility semantics at the view boundary, extend only the isolated `--ui-testing` fixture where deterministic state coverage is needed, and add one focused UI-test class that exercises the three primary screens. Do not introduce product state that has no real model transition; record non-applicable states explicitly in the QA matrix.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, XcodeGen, macOS Accessibility APIs.

---

### Task 1: Establish focused accessibility regressions

**Files:**

- Create: `Tests/WhisperUITests/AccessibilityUITests.swift`
- Modify: `Sources/UI/AppUITestEnvironment.swift`
- Modify: `project.yml` only through `xcodegen generate`

**Step 1: Write the failing UI tests**

Add a launch helper using the existing secret-free `--ui-testing`, `--permissions-granted`, and valid fake-key arguments. Cover these behaviors in a compact test class:

- Home, Modes, and Settings expose their primary controls with meaningful names.
- Sidebar rows, mode actions, and form/action controls have practical 44-point hit targets.
- selected, disabled, empty, failed, saving/testing, shortcut-conflict, and permission states contain visible text instead of color-only meaning.
- the supported minimum window size retains access to long content through scrolling.
- the three primary destinations pass the relevant XCTest accessibility audit categories, excluding only findings documented with a concrete platform reason.

Add deterministic UI fixture arguments only for states that cannot be reached cheaply through public controls. Fake text must remain numeric or generic and must never resemble a real key, transcript, or instruction.

**Step 2: Regenerate the project and prove the regression**

Run:

```bash
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperUITests/AccessibilityUITests
```

Expected: the focused suite fails on the existing undersized or unnamed controls before production fixes.

### Task 2: Apply the smallest evidence-backed UI fixes

**Files:**

- Modify: `Sources/UI/AppRootView.swift`
- Modify: `Sources/UI/Home/HomeView.swift`
- Modify: `Sources/UI/Modes/ModesListView.swift`
- Modify: `Sources/UI/Modes/ModeEditorView.swift`
- Modify: `Sources/UI/Settings/SettingsView.swift`
- Modify: `Sources/UI/Components/PermissionRow.swift`
- Modify: `Sources/UI/Components/ShortcutRecorderView.swift` only if the regression demonstrates a gap

**Step 1: Correct target sizes and focus semantics**

Raise practical interactive rows and compact action labels to a 44-point minimum without changing the approved layout direction. Retain native button styles and focus rings. Give navigation and mode rows explicit selected values where XCTest or VoiceOver does not expose the state reliably.

**Step 2: Correct VoiceOver output and state announcements**

Hide decorative status symbols, combine each textual status into one meaningful accessibility element, and mark changing save/test/error/conflict messages as live status content using native SwiftUI accessibility traits. Preserve adjacent repair and action buttons as separate focusable controls.

**Step 3: Make long content resilient**

Allow titles, state messages, and descriptive content to wrap or scroll at the supported `1120 x 760` minimum window size. Do not redesign the cards or navigation.

**Step 4: Run the focused regression**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperUITests/AccessibilityUITests
```

Expected: all focused accessibility UI tests pass.

### Task 3: Complete manual QA and durable evidence

**Files:**

- Create: `docs/testing/evidence/WH-M3-003/qa.md`
- Create: `docs/testing/evidence/WH-M3-003/home.png`
- Create: `docs/testing/evidence/WH-M3-003/modes.png`
- Create: `docs/testing/evidence/WH-M3-003/settings.png`
- Modify: `docs/implementation/tasks/m3-main-ui.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `docs/implementation/roadmap.md`

**Step 1: Perform screenshot-first manual inspection**

Launch the exact Debug app with isolated UI-test storage. At the supported minimum window size, inspect Home, Modes, and Settings screenshots for hierarchy, clipping, contrast-dependent meaning, disabled/error/permission messaging, and target spacing. Save only secret-free fixture screenshots.

**Step 2: Perform keyboard and accessibility-tree inspection**

Navigate the primary screens with the keyboard, confirm visible native focus, inspect VoiceOver/AX names, values, selected states, and order, and verify scroll access to long content. Confirm reduced-motion behavior uses no required custom animation. Record facts and any platform limitations; do not claim complete accessibility conformance from screenshots alone.

**Step 3: Run the task quality gates**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperUITests/AccessibilityUITests
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" build
git diff --check
```

Expected: focused UI suite, build, and diff check all pass. The next milestone-review task will run the complete scheme.

**Step 4: Review and document**

Review the full diff for secrets and task-scope drift. Write the state matrix and manual checklist to `qa.md`; mark `WH-M3-003` done only when acceptance criteria are supported by evidence; update backlog and roadmap status.

**Step 5: Deliver to `origin/master`**

Run the repository account guard, using GitHub account `yurybv`, HTTPS remote `https://github.com/yurybv/whisper.git`, and branch `master`. Commit with a focused Conventional Commit message, push directly to `master`, fetch, and verify the commit is present on `origin/master` before selecting `WH-M3-004`.
