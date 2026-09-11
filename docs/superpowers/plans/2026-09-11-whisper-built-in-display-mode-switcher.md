# Built-in Display Mode Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Command-Shift-K show a usable mode switcher centered on the Mac's built-in display.

**Architecture:** Keep display selection and frame placement inside `ModeSwitcherPanel`. Resolve the built-in `NSScreen` with Core Graphics, calculate a centered frame from its visible bounds, then activate Whisper and order the panel key and front while preserving the existing focus-restoration lifecycle.

**Tech Stack:** Swift 6, AppKit, Core Graphics, SwiftUI, XCTest

## Global Constraints

- Support macOS 15 and the repository's existing Swift/Xcode configuration.
- Add no dependency and no new persisted setting.
- Preserve Command-Shift-K handling and Escape focus restoration.
- Never log shortcut input, dictated text, transcripts, secrets, or authorization headers.

---

### Task 1: Place the mode switcher on the built-in display

**Files:**
- Modify: `Sources/UI/ModeSwitcher/ModeSwitcherController.swift`
- Modify: `Tests/WhisperTests/UI/OverlayLifecycleTests.swift`
- Modify: `docs/testing/evidence/WH-M3-001/qa.md`
- Modify: `docs/implementation/tasks/m3-main-ui.md`
- Modify: `docs/implementation/roadmap.md`

**Interfaces:**
- Consumes: `NSScreen.screens`, `NSScreen.visibleFrame`, `CGDisplayIsBuiltin(_:)`, and the existing `ModeSwitcherPanelLifecycle`.
- Produces: `ModeSwitcherPanel.frame(panelSize:visibleFrame:) -> NSRect` and built-in-display presentation through `ModeSwitcherPanel.present()`.

- [x] **Step 1: Write the failing frame test**

```swift
func testModeSwitcherFrameIsCenteredInsideVisibleScreen() {
    let frame = ModeSwitcherPanel.frame(
        panelSize: NSSize(width: 560, height: 452),
        visibleFrame: NSRect(x: 120, y: 80, width: 1_440, height: 900)
    )

    XCTAssertEqual(frame.origin.x, 560)
    XCTAssertEqual(frame.origin.y, 304)
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/OverlayLifecycleTests/testModeSwitcherFrameIsCenteredInsideVisibleScreen
```

Expected: compilation fails because `ModeSwitcherPanel.frame(panelSize:visibleFrame:)` does not exist.

- [x] **Step 3: Implement built-in-display placement**

Add a pure frame calculation and a built-in-screen resolver to `ModeSwitcherPanel`. In `present()`, resolve the built-in screen with `CGDisplayIsBuiltin`, fall back to `NSScreen.main` and `NSScreen.screens.first`, set the centered frame using the panel's current size, activate Whisper, then call `makeKeyAndOrderFront(nil)` and `orderFrontRegardless()`.

- [x] **Step 4: Run focused and full automated checks**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/OverlayLifecycleTests
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test
git diff --check
```

Expected: all tests pass and `git diff --check` prints no output.

- [ ] **Step 5: Perform live two-display QA and update evidence**

Build and launch the exact current app bundle. With another application active on the Mac's built-in display, press Command-Shift-K and verify the switcher is centered on that display. Press Escape and verify the prior application regains focus. Record the bundle path, permission state, and result in the WH-M3-001 evidence and task records.

- [ ] **Step 6: Commit and deliver**

Run the repository account guard, commit the focused change with a Conventional Commit message, push directly to `master`, and verify the commit hash equals `origin/master`.
