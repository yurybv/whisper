# WH-M3-003 UI state and accessibility verification

Date: 2026-09-14. Mac: Apple Silicon, macOS 26.5.

## Automated evidence

- `xcodegen generate` passed after adding `AccessibilityUITests`.
- `xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' test -only-testing:WhisperUITests/AccessibilityUITests` passed **5 UI tests**, zero failures.
- Result bundle: `/Users/yurybogdanov/Library/Developer/Xcode/DerivedData/Whisper-cvohsozztgjbkycfgedqypyhclkz/Logs/Test/Test-Whisper-2026.09.14_12-45-37-+0400.xcresult`.
- The focused suite verifies 44-point custom navigation/action targets, hidden decorative status symbols, explicit state text, the minimum `1120 x 760` window, long mode content, and macOS accessibility audit categories for action, element detection, parent/child relationships, and sufficient descriptions.
- The system audit permits only identified XCTest/SwiftUI platform findings: anonymous layout groups, the system Touch Bar container, native SwiftUI menu/picker action reports, and an anonymous SwiftUI parent-child group. Named application controls outside that exact type list remain test failures. The same native menu and picker controls expose names, values, and actions in the live AX tree.
- `xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' build` and `codesign --verify --deep --strict` passed for the Debug app.

## State matrix

| State | Evidence |
|---|---|
| Loading | Settings exposes `Testing connection…` while the isolated connection fixture is suspended. Home changes to `Checking OpenAI connection` from the same model state. |
| Empty | Home renders `No history yet` plus an explanatory next step. |
| Populated | Modes renders the protected Default mode and an isolated long custom mode; the editor exposes the complete stored values through AX. |
| Failed | Settings renders `Connection could not be verified…` with warning symbol and text; model-level tests continue to cover safe Keychain and persistence failures. |
| Saving | Mode and API-key writes are local synchronous transactions, so the UI does not invent an indeterminate spinner. Save remains disabled until input is changed and valid; a failed write persists a named error beside its action. |
| Conflict | The isolated shortcut fixture renders `That shortcut is already used by Record Meeting.` and keeps the prior shortcut. |
| Disabled | The long custom mode renders `Disabled`; its toggle value is exposed as off, and unchanged editor Save/Cancel actions are disabled. Default fields are disabled and its built-in status is explicit. |
| Permission | Home and Settings render each missing permission as `Not Granted` with a warning symbol; repair actions keep exact names. Unaffected destinations remain usable. |

Every warning/success/selection state pairs color with text, an SF Symbol, an accessibility value, or a native selected trait. Decorative status symbols are hidden from accessibility so they no longer announce the meaningless label `Selected`.

## Screenshot-first visual inspection

- [Home](home.png) uses the denied-permission and empty-history fixture. The readiness headline is explicit, permission rows contain text, and the screen remains readable and scrollable at the supported minimum content size.
- [Modes](modes.png) uses a long disabled-mode fixture. The mode name wraps in the list and heading, instructions wrap inside their scrollable editor, `Disabled` is textual, and mode action menus retain a 44-point target.
- [Settings](settings.png) uses failed-connection and shortcut-conflict fixtures. The saved key remains masked, the failure text is visible beside its action, and lower settings remain reachable by scrolling.
- Screenshots contain only in-memory fixtures and generic numeric content. They do not read production Keychain, permissions, history, transcripts, instructions, or the network.

## Keyboard, VoiceOver, and motion checklist

- The AX traversal order is sidebar navigation, destination content, then the standard window toolbar. Within each destination, headings precede named controls and state values.
- Sidebar items are named buttons with selected traits. Mode rows expose concise labels plus built-in, active, disabled, and language values; action menus remain separate controls.
- Home status decoration no longer creates duplicate `Selected` image stops. The toolbar microphone is one text element named `Current microphone` with its current value.
- Permission rows expose one static-text element with the permission name and state, followed by a separate named repair button in Settings.
- API connection, Keychain, launch-at-login, shortcut-conflict, mode-validation, mode-persistence, history, and permission changes use the `updatesFrequently` trait for status announcements.
- In the host's current macOS `AppleKeyboardUIMode=1` policy, Tab moved focus from Mode name to Custom instructions and the native insertion focus indicator was visible. macOS intentionally excludes buttons from the Tab loop unless the owner enables system Keyboard Navigation for all controls; their keyboard/VoiceOver actions were checked through the system audit and live AX tree without changing that owner setting.
- No custom animation or transition exists in Home, Modes, Settings, or their shared components. Reduced Motion therefore removes no required context; only native system control motion remains.
- Long content was checked at a measured `1120 x 760` content size (`1120 x 812` including title bar). It wraps or remains available through native field/editor scrolling; no destination or action is lost.

## Audit corrections

- Raised sidebar navigation and mode action hit regions to 44 points while preserving the approved native layout.
- Added heading traits, explicit mode labels/values/selection, permission labels/values, and live status traits.
- Hid decorative Home and toolbar symbols from accessibility and kept their meaning in adjacent text.
- Raised mode detail rows to a practical 44-point minimum and preserved native focus behavior.
- Added deterministic, secret-free testing fixtures for loading/failure, shortcut conflict, denied permissions, and long disabled content.

## Result

The primary non-recording screens satisfy the WH-M3-003 acceptance criteria with focused automation plus screenshot and AX evidence. The complete scheme remains intentionally deferred to the immediately following `WH-M3-004` milestone review.
