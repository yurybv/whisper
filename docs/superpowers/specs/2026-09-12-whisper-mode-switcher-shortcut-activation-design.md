# Whisper Mode Switcher Shortcut and Activation Design

## Context

The current default, Command-Shift-K, collides with Finder's **Go > Network** command. Physical-key tracing also showed a separate defect: the event reaches Whisper's event tap, shortcut state machine, action router, and mode-switcher controller, but Finder can remain the active application after the panel is ordered onscreen. In that state the panel reports itself visible without becoming the key window, so the owner sees no usable switcher.

The replacement shortcut is Control-Command-M. `M` provides a mnemonic for Mode, the combination is not assigned by the enabled macOS symbolic shortcuts on the owner's Mac, and it is not present in the owner's saved Rectangle bindings. No global shortcut can be guaranteed free in every third-party application, so Whisper will continue to support later reassignment through Settings.

## Approved behavior

- Control-Command-M is the default **Change Mode** shortcut everywhere Whisper presents or handles that command.
- Pressing it while another application is frontmost opens the switcher centered on the built-in display, activates Whisper, makes the panel key, and focuses search.
- Escape closes the switcher and restores the application that was frontmost before the switcher opened.
- Repeated presentation does not replace the originally captured application used for focus restoration.
- Existing or future explicitly customized shortcuts remain user-owned. Only the legacy default Command-Shift-K is eligible for automatic replacement if persisted shortcut settings exist when shortcut persistence ships.
- The meeting and push-to-talk shortcuts do not change.

## Shortcut selection

The following alternatives were rejected:

- Command-Option-K conflicts with the owner's Rectangle configuration and with Keychain Access's Ticket Viewer command.
- Control-Command-K is not a macOS-wide shortcut, but Apple Notes uses it for the shared-note activity list.
- Control-Command-J appears unassigned, but has no useful connection to the action and is harder to remember.

Control-Command-M is therefore the smallest memorable choice with no detected system or local Rectangle collision.

## Implementation design

`AppSettings.defaults` will define Change Mode as the `M` key with Control and Command modifiers. The shortcut key model will add an `M` key constant. Onboarding copy, menu-bar hints, tests, the approved MVP design, and the implementation plan will use the same label so the UI and runtime cannot disagree.

The current milestone does not yet persist configurable shortcuts, so there is no stored value to migrate in this change. The later Settings persistence work must treat an explicitly saved value as authoritative and may replace only an exact legacy Command-Shift-K default.

`ModeSwitcherPanel.present()` will first order the panel onscreen, then call `NSApplication.activate(ignoringOtherApps: true)`, and finally request key-window status. Ordering is intentional: live AppKit inspection showed that forced activation succeeds for the menu-bar accessory only after it owns a visible window, while cooperative `NSApplication.activate()` can leave Finder or another application active. The existing built-in-display placement remains unchanged. The post-layout presentation pass will request key-and-front status again while the panel is visible. Focus restoration continues to use `NSRunningApplication` because it targets the previously active external application rather than Whisper itself.

## Verification

Automated coverage will verify:

- the default shortcut is Control-Command-M and still round-trips through Codable;
- the hotkey state machine emits Change Mode for Control-Command-M and not for Command-Shift-K;
- onboarding and menu-bar surfaces display the new shortcut;
- the mode-switcher panel remains key-capable and retains its built-in-display placement and restoration lifecycle behavior.

Manual QA on the rebuilt signed bundle will start with Finder frontmost, physically press Control-Command-M, verify the panel appears centered on the built-in display with search focused, then press Escape and verify focus returns to Finder. The check will also confirm Finder's Network command does not run and Rectangle does not react.

## Scope boundaries

This change does not add general system-wide conflict discovery, alter other shortcuts, redesign the mode switcher, or implement the future Settings shortcut editor. It fixes the approved default and the activation path needed to make that default observable.
