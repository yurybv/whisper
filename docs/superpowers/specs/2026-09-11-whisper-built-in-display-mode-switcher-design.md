# Built-in Display Mode Switcher Design

> Shortcut update (2026-09-12): the presentation behavior in this document remains current, but the default shortcut is now Control-Command-M. See `2026-09-12-whisper-mode-switcher-shortcut-activation-design.md`.

## Problem

The global Command-Shift-K event reaches `AppRuntime.showModeSwitcher()`, but the panel is not reliably visible where the owner is working. Live tracing confirmed the native event tap, shortcut state machine, router, and controller are all invoked. The panel uses `NSWindow.center()`, which does not express the product requirement for a two-display setup and may run before the hosted SwiftUI view has settled on its final frame.

## Approved behavior

- Control-Command-M always presents the mode switcher on the Mac's built-in display.
- The external display is never selected for this panel, even when its application is frontmost.
- The panel is centered inside the built-in display's visible frame after its content controller is installed.
- Whisper activates and the panel becomes key so search and Escape work immediately.
- Escape closes the panel and restores the application that was active before the panel opened.
- If macOS reports no built-in display, fall back to the main screen and then the first available screen.

## Design

`ModeSwitcherPanel` owns display selection because placement is a presentation concern. It identifies the built-in `NSScreen` through the screen's `NSScreenNumber` and `CGDisplayIsBuiltin`. A pure frame helper centers the panel's current frame size within the selected screen's `visibleFrame`, which keeps the menu bar and Dock clear and makes placement unit-testable.

Presentation activates Whisper, applies the calculated frame, and orders the panel key and front. The existing `ModeSwitcherPanelLifecycle` continues to capture the previous application only on the first show and restores it on close.

## Verification

- Unit-test centering with a non-zero screen origin to cover multi-display coordinates.
- Run the focused overlay lifecycle tests and the full Whisper test suite.
- On the two-display Mac, put another application on the built-in display, press Control-Command-M, verify the panel appears centered there, press Escape, and verify focus returns to that application.
