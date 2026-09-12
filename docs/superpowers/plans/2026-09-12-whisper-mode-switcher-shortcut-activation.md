# Whisper Mode Switcher Shortcut and Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Control-Command-M open a visible, keyboard-ready mode switcher without colliding with Finder or the owner's Rectangle shortcuts.

**Architecture:** Keep shortcut identity in `AppSettings.defaults` and consume it through the existing hotkey state machine and native event tap. Keep screen placement in `ModeSwitcherPanel`; order the panel visible before forcing `NSApplication.activate(ignoringOtherApps: true)`, then request immediate and deferred key-window status. Preserve the current lifecycle that restores the previously frontmost application.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Core Graphics `CGEventTap`, XCTest/XCUITest, Xcode 26, macOS 15+

**Spec:** `docs/superpowers/specs/2026-09-12-whisper-mode-switcher-shortcut-activation-design.md`

## Global Constraints

- Control-Command-M is the default Change Mode shortcut; Right Option, Command-Shift-R, and Escape do not change.
- The switcher remains centered on the built-in display and falls back to the main or first screen only when no built-in display is reported.
- Escape restores the application that was frontmost before the first presentation.
- Add no dependency and no new persisted setting.
- Do not add general global-shortcut discovery in this task.
- Never log shortcut input, dictated text, transcripts, secrets, or authorization headers.
- Follow TDD: each production behavior change requires a focused failing test observed before implementation.

---

### Task 1: Replace the Change Mode Default and User-Facing Labels

**Files:**
- Modify: `docs/implementation/tasks/m3-main-ui.md:3-25`
- Modify: `Tests/WhisperTests/Core/ShortcutTests.swift:20-27`
- Modify: `Tests/WhisperTests/Hotkeys/HotkeyStateMachineTests.swift:40-50, 235-275, 355-475`
- Modify: `Tests/WhisperUITests/OnboardingUITests.swift:18-21`
- Modify: `Sources/Core/Shortcut.swift:10-17`
- Modify: `Sources/Core/AppSettings.swift:42-52`
- Modify: `Sources/UI/Onboarding/OnboardingView.swift:149-153`
- Modify: `Sources/UI/MenuBar/MenuBarContentView.swift:121-124`

**Interfaces:**
- Consumes: `Shortcut.Key`, `Shortcut.Modifiers`, `AppSettings.defaults.shortcuts`, `HotkeyStateMachine.consume(_:)`
- Produces: `Shortcut.Key.m` with macOS virtual key code `46`; `.changeMode` defaulted to `Shortcut(key: .m, modifiers: [.control, .command])`

- [x] **Step 1: Return the resumed task to implementation status**

Change `WH-M3-001` from `Status: review` to `Status: in-progress` and replace its obsolete remaining-acceptance sentence with a blocker note stating that the approved Control-Command-M change and AppKit activation fix are being implemented. Do not unblock `WH-M3-002` yet.

- [x] **Step 2: Write failing default and routing tests**

Change the literal expectation in `ShortcutTests.testDefaultShortcutsUseApprovedKeysAndModifiers()` to:

```swift
.changeMode: Shortcut(key: .m, modifiers: [.control, .command]),
```

Change `HotkeyStateMachineTests.testChangeModeInvokesOnlyOnInitialKeyDown()` to exercise the approved binding and prove the legacy Finder binding is not claimed:

```swift
func testChangeModeUsesControlCommandMAndIgnoresLegacyFinderShortcut() {
    var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
    let flags: Shortcut.Modifiers = [.control, .command]

    XCTAssertEqual(
        machine.consume(
            .keyDown(keyCode: Shortcut.Key.m.keyCode, flags: flags, isRepeat: false)
        ),
        .invoked(.changeMode)
    )
    XCTAssertNil(
        machine.consume(
            .keyDown(keyCode: Shortcut.Key.m.keyCode, flags: flags, isRepeat: true)
        )
    )
    XCTAssertNil(
        machine.consume(.keyUp(keyCode: Shortcut.Key.m.keyCode, flags: flags))
    )
    XCTAssertNil(
        machine.consume(.keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: false))
    )
}
```

Update native-monitor and monitor-recovery tests that intentionally exercise the default Change Mode binding to post virtual key `46` with Core Graphics flags `[.maskControl, .maskCommand]` or normalized flags `[.control, .command]`. Keep shortcut-capture tests that deliberately record Command-Shift-K unchanged because they verify arbitrary reassignment.

- [x] **Step 3: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test \
  -only-testing:WhisperTests/ShortcutTests \
  -only-testing:WhisperTests/HotkeyStateMachineTests \
  -only-testing:WhisperTests/GlobalHotkeyMonitorTests \
  -only-testing:WhisperTests/CGEventHotkeyMonitorTests
```

Expected: FAIL because `Shortcut.Key.m` does not exist and the current default still routes Command-Shift-K.

- [x] **Step 4: Implement the new key and default**

Add the physical M key to `Shortcut.Key`:

```swift
static let m = Key(46)
```

Change the default in `AppSettings.defaults`:

```swift
.changeMode: Shortcut(key: .m, modifiers: [.control, .command]),
```

- [x] **Step 5: Run the focused unit tests and verify GREEN**

Run the command from Step 3.

Expected: PASS for the four focused test classes with the new default consumed and the legacy shortcut passed through.

- [x] **Step 6: Write the failing onboarding UI expectation**

Change `OnboardingUITests.testFirstLaunchCompletesFourStepsAndCanPreviewFromSettings()` to require:

```swift
XCTAssertTrue(app.staticTexts["Control-Command-M"].exists)
```

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test \
  -only-testing:WhisperUITests/OnboardingUITests/testFirstLaunchCompletesFourStepsAndCanPreviewFromSettings
```

Expected: FAIL because the Ready screen still displays `Command-Shift-K`.

- [x] **Step 7: Update onboarding and menu-bar labels**

Use `Control-Command-M` on the onboarding Ready screen and `⌃⌘M` beside the menu-bar Change Mode action:

```swift
Text("Control-Command-M")
```

```swift
menuButton(
    "Change Mode",
    systemImage: "square.grid.2x2",
    shortcut: "⌃⌘M",
    action: onChangeMode
)
```

- [x] **Step 8: Run the focused UI test and verify GREEN**

Run the command from Step 6.

Expected: PASS with the new shortcut visible on the Ready screen.

---

### Task 2: Present the Mode Switcher Before Forcing Activation

**Files:**
- Modify: `Tests/WhisperTests/UI/OverlayLifecycleTests.swift:56-130`
- Modify: `Sources/UI/ModeSwitcher/ModeSwitcherController.swift:6-75`

**Interfaces:**
- Consumes: AppKit `NSApplication.activate(ignoringOtherApps:)`, `NSPanel.orderFrontRegardless()`, `NSPanel.makeKeyAndOrderFront(_:)`, existing `ModeSwitcherPanelLifecycle`
- Produces: `ApplicationActivating.activate(ignoringOtherApps:)` and `ModeSwitcherPanel.init(application:)`, defaulting to `NSApplication.shared`

- [x] **Step 1: Write a failing activation-boundary test**

Add a test double at the bottom of `OverlayLifecycleTests.swift`:

```swift
@MainActor
private final class FakeApplicationActivator: ApplicationActivating {
    private(set) var activationRequests: [Bool] = []
    private(set) var panelVisibilityAtActivation: [Bool] = []
    var isPanelVisible: () -> Bool = { false }

    func activate(ignoringOtherApps: Bool) {
        activationRequests.append(ignoringOtherApps)
        panelVisibilityAtActivation.append(isPanelVisible())
    }
}
```

Add this test to `OverlayLifecycleTests`:

```swift
func testModeSwitcherForcesApplicationActivationWhenPresented() {
    let application = FakeApplicationActivator()
    let panel = ModeSwitcherPanel(application: application)
    application.isPanelVisible = { panel.isVisible }

    panel.present()

    XCTAssertEqual(application.activationRequests, [true])
    XCTAssertEqual(application.panelVisibilityAtActivation, [true])
    panel.dismiss()
}
```

This fake replaces only the external AppKit activation side effect; the real `ModeSwitcherPanel.present()` placement and window-ordering code still executes. The visibility assertion protects the ordering discovered through live AppKit inspection: the menu-bar accessory must own a visible panel before forced activation is requested.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test \
  -only-testing:WhisperTests/OverlayLifecycleTests/testModeSwitcherForcesApplicationActivationWhenPresented
```

Expected: FAIL to compile because `ApplicationActivating` and `ModeSwitcherPanel.init(application:)` do not exist.

- [x] **Step 3: Implement AppKit application activation**

Add the narrow boundary and real conformance:

```swift
@MainActor
protocol ApplicationActivating: AnyObject {
    func activate(ignoringOtherApps: Bool)
}

extension NSApplication: ApplicationActivating {}
```

Store the dependency in `ModeSwitcherPanel` and default it to the real application:

```swift
private let application: any ApplicationActivating

init(application: any ApplicationActivating = NSApplication.shared) {
    self.application = application
    super.init(
        contentRect: NSRect(origin: .zero, size: Self.contentSize),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: true
    )
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .floating
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    isReleasedWhenClosed = false
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
}
```

Replace self-activation through `NSRunningApplication.current` with visible-first forced activation:

```swift
orderFrontRegardless()
application.activate(ignoringOtherApps: true)
makeKeyAndOrderFront(nil)
```

In the existing deferred visible-panel block, preserve recentering and replace `orderFrontRegardless()` with:

```swift
makeKeyAndOrderFront(nil)
```

Do not change `NSRunningApplication.restoreActivation()`; it correctly targets the previously frontmost external application.

- [x] **Step 4: Run overlay lifecycle tests and verify GREEN**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test \
  -only-testing:WhisperTests/OverlayLifecycleTests
```

Expected: PASS, including application activation, key capability, built-in-display placement, and focus-restoration lifecycle tests.

- [x] **Step 5: Run mode-switcher UI regressions**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test \
  -only-testing:WhisperUITests/ModeSwitcherUITests
```

Expected: PASS; arrow/Return activates a mode and Escape closes the utility without terminating it.

---

### Task 3: Synchronize Product Documentation and Deliver WH-M3-001

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-whisper-macos-mvp-design.md:11-17, 161-165`
- Modify: `docs/superpowers/specs/2026-09-11-whisper-built-in-display-mode-switcher-design.md:1-26`
- Modify: `docs/superpowers/plans/2026-08-19-whisper-macos-mvp.md:20-29, 281-286, 832-900, 955-959, 1335-1340`
- Modify: `docs/opendesign/whisper-macos-mvp-prompt.md:69-72, 196-201`
- Modify: `docs/testing/evidence/WH-M3-001/qa.md`
- Modify: `docs/implementation/tasks/m3-main-ui.md:3-40`
- Modify: `docs/implementation/task-backlog.md:42-51`
- Modify: `docs/implementation/roadmap.md:67-86`
- Keep: `docs/superpowers/specs/2026-09-12-whisper-mode-switcher-shortcut-activation-design.md`
- Keep: `docs/superpowers/plans/2026-09-12-whisper-mode-switcher-shortcut-activation.md`

**Interfaces:**
- Consumes: verified runtime behavior and test results from Tasks 1 and 2
- Produces: current product/task documentation, completed `WH-M3-001`, and unblocked `WH-M3-002`

- [x] **Step 1: Update shortcut source-of-truth documentation**

Replace current behavioral references to Command-Shift-K with Control-Command-M in the approved MVP design, main implementation plan, and Open Design prompt. In the 2026-09-11 placement design, retain the original shortcut only in historical problem context and add a supersession note linking to the 2026-09-12 shortcut-and-activation design; use Control-Command-M for current approved behavior and QA.

- [x] **Step 2: Run the complete automated scheme**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test
```

Expected: PASS for all unit and UI tests with no test failure. Record the exact test counts in `docs/testing/evidence/WH-M3-001/qa.md` and `docs/implementation/tasks/m3-main-ui.md`.

- [x] **Step 3: Build and verify the exact QA bundle**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' \
  -derivedDataPath /tmp/whisper-control-command-m build
codesign --verify --deep --strict /tmp/whisper-control-command-m/Build/Products/Debug/Whisper.app
```

Expected: `BUILD SUCCEEDED` and codesign exits `0`. Launch this exact bundle and confirm Accessibility and Input Monitoring grants refer to it.

- [x] **Step 4: Perform physical shortcut QA**

With Finder frontmost on the built-in display, physically press Control-Command-M. Verify:

1. Finder does not open a command and Rectangle does not move a window.
2. Whisper becomes active.
3. The `560`-point-wide switcher appears centered on the built-in display.
4. Search accepts keyboard input immediately.
5. Escape closes the panel and Finder becomes frontmost again.

Record the exact bundle path, permission state, foreground application transitions, panel frame, and outcome in `docs/testing/evidence/WH-M3-001/qa.md` without recording typed shortcut events or user content.

- [x] **Step 5: Close WH-M3-001 only after physical QA passes**

Set `WH-M3-001` to `done`, remove its blocker, and add a dated shortcut/activation verification note. Set `WH-M3-002` to `ready` in both `docs/implementation/tasks/m3-main-ui.md` and `docs/implementation/task-backlog.md`. Update the roadmap to state that onboarding and physical Control-Command-M verification passed. If physical QA fails, keep `WH-M3-001` in `review` with the exact observed blocker and leave `WH-M3-002` blocked.

- [x] **Step 6: Review the diff and run repository completion checks**

Run:

```bash
git diff --check
git status --short
git diff -- Sources Tests docs
```

Expected: no whitespace errors, no unrelated changes, no secret or user-content logging, and documentation consistent with the verified result.

- [x] **Step 7: Run the repository/account guard**

Run exactly:

```bash
gh api user --jq .login
git remote get-url origin
git branch --show-current
git status --short
```

Required: account `yurybv`, remote `https://github.com/yurybv/whisper.git`, and branch `master`. Stop before committing or pushing if any value differs.

- [x] **Step 8: Commit and push the focused task**

Stage only the files listed by this plan and commit with:

```text
fix(hotkeys): move mode switcher to control-command-m

- avoid Finder and Rectangle shortcut collisions
- activate the mode switcher as a key AppKit panel
- update shortcut UI, tests, and milestone QA records
```

Push directly to `origin/master`, then run:

```bash
git fetch origin master
git status --short
git rev-parse HEAD
git rev-parse origin/master
```

Expected: clean status and identical local/origin commit IDs. Do not claim completion until the final commit is present on `origin/master`.
