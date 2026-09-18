# Built-In Modes and Keyboard-First Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three protected built-in modes and make mode activation obvious: the Modes-list circle activates directly, while repeated Control-Command-M cycles the open switcher without removing arrow-key navigation.

**Architecture:** Represent all built-ins as canonical `ModeDefinition` values with stable IDs, derive protection from built-in identity rather than `isDefault`, and idempotently reconcile them at startup. Keep the switcher's pure selection behavior in its model/view model, while its controller distinguishes a global-shortcut repeat from ordinary Home/menu presentation.

**Tech Stack:** Swift 6.3, SwiftData, SwiftUI, AppKit, Observation, XCTest/XCUITest, XcodeGen/Xcodebuild.

**Spec:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md`

## Global Constraints

- Complete `WH-M6-010` and push it before changing `WH-M6-011` to `in-progress`.
- Copy both owner-provided prompt bodies byte-for-byte from the spec; do not paraphrase them.
- Built-ins are protected from edit/rename/delete but remain duplicable. `isDefault` continues to mean only the fallback Default mode.
- Do not reset a valid active custom or built-in mode while reconciling presets.
- A name collision must preserve the user's mode ID and content under a deterministic custom suffix.
- Repeated Control-Command-M advances selection only while the switcher is already visible. Home and menu actions only open it.
- Follow red-green-refactor and run the repository account guard before each final push.

---

## Part A — WH-M6-010: Protected built-in presets

## Task 1: Define canonical built-ins and protection semantics

**Files:**

- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `Sources/Core/ModeDefinition.swift`
- Modify: `Tests/WhisperTests/Core/ModeRulesTests.swift`

- [ ] Confirm `WH-M6-009` is `done`, then change only `WH-M6-010` from `blocked` to `in-progress` in both task records.

- [ ] Add failing tests that assert the exact canonical contract:

```swift
func testBuiltInModesHaveStableIdentityOrderAndProtection() {
    XCTAssertEqual(
        ModeDefinition.builtInModes.map(\.id.uuidString),
        [
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
            "00000000-0000-0000-0000-000000000003"
        ]
    )
    XCTAssertEqual(
        ModeDefinition.builtInModes.map(\.name),
        [
            "Default",
            "Russian → English — Work / Technical",
            "Russian → English — Slack / Friendly"
        ]
    )
    XCTAssertEqual(ModeDefinition.builtInModes.map(\.sortIndex), [0, 1, 2])
    XCTAssertEqual(ModeDefinition.builtInModes.map(\.languageHint), [nil, "ru", "ru"])
    XCTAssertTrue(ModeDefinition.builtInModes.allSatisfy(\.isBuiltIn))
    XCTAssertEqual(ModeDefinition.builtInModes.filter(\.isDefault), [.defaultMode])
}
```

Also compare both new `instructions` strings exactly with the spec fixtures, including blank lines, punctuation, apostrophes, arrow/em dash characters, emoji, and final period.

- [ ] Run the focused tests and confirm failure before production constants exist:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/ModeRulesTests
```

- [ ] In `ModeDefinition`, add stable IDs ending `0002` and `0003`, exact names/instructions, `languageHint: "ru"`, `isDefault: false`, `isEnabled: true`, sort indexes 1 and 2, and epoch timestamps. Expose:

```swift
static let builtInModes: [ModeDefinition] = [
    defaultMode,
    russianEnglishWorkTechnicalMode,
    russianEnglishSlackFriendlyMode
]

static let builtInIDs = Set(builtInModes.map(\.id))

var isBuiltIn: Bool {
    Self.builtInIDs.contains(id)
}
```

- [ ] Update deletion/update validation so every `isBuiltIn` mode is protected, while only Default remains the fallback. Add tests that all three built-ins reject editing/deletion and a duplicate created from any built-in remains editable.

- [ ] Re-run `ModeRulesTests` and confirm all pass.

## Task 2: Reconcile all built-ins without deleting custom modes

**Files:**

- Modify: `Sources/Persistence/ModeRepository.swift`
- Modify: `Tests/WhisperTests/Persistence/PersistenceTests.swift`

- [ ] Replace the old default-only tests with failing tests for:

  - an empty store seeds exactly the three canonical built-ins in order;
  - running the seeder twice leaves exactly three built-ins and no duplicates;
  - canonical rows with stale names/instructions/language/enabled/order are repaired by stable ID;
  - unrelated custom modes retain ID, content, enabled state, and sort order;
  - a valid active custom mode remains active after seeding;
  - each exact-name custom collision is renamed deterministically to `<name> (Custom)`, then `(Custom 2)`, and the canonical built-in is inserted;
  - deletion of the active custom mode still falls back to Default.

- [ ] Run `PersistenceTests` and confirm the new seed tests fail against `seedDefaultMode()`.

- [ ] Replace `seedDefaultMode()` with `seedBuiltInModes()` and call it from `activeMode()` and startup. Reconcile in one context save:

  1. Fetch all modes once.
  2. For each canonical built-in in order, find only its stable ID as canonical keeper.
  3. Before inserting/repairing it, rename any non-built-in exact normalized-name collision using the first available deterministic custom suffix; preserve that row's ID, instructions, language, enabled state, and timestamps except the name/update time required by the rename.
  4. Insert a missing canonical row or overwrite all canonical fields on the stable-ID row.
  5. Never delete a custom row merely because its old name or `isDefault` flag resembles a built-in.
  6. Normalize accidental legacy `isDefault` flags so only stable Default ID is default.
  7. Save once. Do not write `activeModeID` unless its current value is missing/disabled and fallback is required.

- [ ] Keep a temporary deprecated wrapper only if an existing call site/test cannot move atomically; remove it before finishing so production has one seeding API.

- [ ] Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/PersistenceTests \
  -only-testing:WhisperTests/ModeRulesTests
```

Expected: all exact-content, collision, idempotency, active-selection, and existing persistence tests pass.

## Task 3: Protect and display every built-in in Modes UI

**Files:**

- Modify: `Sources/UI/Modes/ModesModel.swift`
- Modify: `Sources/UI/Modes/ModeEditorView.swift`
- Modify: `Sources/UI/Modes/ModesListView.swift`
- Modify: `Sources/UI/AppUITestEnvironment.swift`
- Modify: `Tests/WhisperTests/UI/ModesModelTests.swift`
- Modify: `Tests/WhisperUITests/ModesUITests.swift`

- [ ] Add failing model tests proving `canRename`, `canDelete`, and editor save state are false for all three built-ins, and true for a duplicate/custom mode.

- [ ] Change editor protection from `isDefault` to `isBuiltIn` throughout model and view. Rename internal UI state from `isDefault` to `isBuiltIn` where it represents editability; keep `isDefault` only for fallback-specific display/logic.

- [ ] Render the `BUILT-IN` badge and Accessibility value for all `mode.isBuiltIn` values. Keep `Duplicate Mode` available on the right detail panel while fields and direct save remain disabled.

- [ ] Update the deterministic UI-test fixture to seed the three built-ins. Add a fresh-app UI test asserting all exact names appear in deterministic order and opening either new preset shows protected instructions plus Duplicate Mode.

- [ ] Run focused model and UI tests:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/ModesModelTests \
  -only-testing:WhisperUITests/ModesUITests
```

- [ ] Run the full gate and diff check:

```bash
./scripts/verify.sh
git diff --check
```

- [ ] Launch the verified package once against a fresh synthetic store and once against an upgraded synthetic store. Confirm exactly three canonical built-ins, preserved custom modes, preserved active selection, exact prompts, and no duplication after a second launch.

- [ ] Mark `WH-M6-010` `done`, record sanitized verification evidence, and commit:

```text
feat(modes): ship Russian-to-English presets

- seed two protected translation modes beside Default
- preserve custom modes and active selection during reconciliation
```

- [ ] Run the account guard, push `master`, and verify the commit on `origin/master` before starting Part B.

---

## Part B — WH-M6-011: Direct activation and shortcut cycling

## Task 4: Make the leading circle the activation control

**Files:**

- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `Sources/UI/Modes/ModesListView.swift`
- Modify: `Tests/WhisperTests/UI/ModesModelTests.swift`
- Modify: `Tests/WhisperUITests/ModesUITests.swift`

- [ ] Change `WH-M6-011` from `blocked` to `in-progress` only after `WH-M6-010` is done and pushed.

- [ ] Add failing UI tests for these separate hit targets:

  1. Clicking `Activate Russian → English — Work / Technical` changes the active value without opening the detail pane or ellipsis menu.
  2. Clicking `Mode row Russian → English — Slack / Friendly` selects/opens that mode without activating it.
  3. `Actions for <mode>` contains Duplicate and permitted Rename/Delete actions but no Activate.
  4. `Activate Mode` remains available in the detail panel for an enabled inactive mode.

- [ ] Refactor `modeRow` into sibling controls. The 44-by-44 leading button calls `model.activateForPresentation(mode.id)` and has:

```swift
.accessibilityIdentifier("Activate \(mode.name)")
.accessibilityLabel("Activate \(mode.name)")
.accessibilityValue(mode.id == model.activeModeID ? "Active" : "Inactive")
```

Disable the activation action for disabled or already-active modes while leaving the state readable to VoiceOver. The remaining row button calls only `model.select(mode.id)`. Remove Activate from the `Menu`; do not change Duplicate/Rename/Delete eligibility.

- [ ] Run focused Modes tests and confirm all pass.

## Task 5: Make repeated global shortcuts advance the open switcher

**Files:**

- Modify: `Sources/UI/ModeSwitcher/ModeSwitcherModel.swift`
- Modify: `Sources/UI/ModeSwitcher/ModeSwitcherController.swift`
- Modify: `Sources/UI/ModeSwitcher/ModeSwitcherView.swift`
- Modify: `Sources/WhisperApp/AppRuntime.swift`
- Modify: `Tests/WhisperTests/UI/ModeSwitcherModelTests.swift`
- Modify: `Tests/WhisperTests/UI/OverlayLifecycleTests.swift`
- Modify: `Tests/WhisperUITests/ModeSwitcherUITests.swift`

- [ ] Add or extend pure-model tests proving `.down` advances and wraps through enabled filtered modes, and that changing the query normalizes selection before repeated cycling.

- [ ] Add a controller/lifecycle regression using the existing fake panel pattern:

```swift
func testFirstShortcutShowsAndSecondShortcutAdvancesWithoutRebuildingPanel() throws
```

Assert that the first shortcut captures the previous application/presents once with the active mode selected; the second shortcut keeps the same view model/panel and changes selection to the next mode; a third/fourth repeat wraps; Return activates the selected ID and closes/restores focus.

- [ ] Add a shortcut-specific controller entry point:

```swift
func handleChangeModeShortcut() throws {
    if lifecycle.isVisible, let viewModel {
        viewModel.move(.down)
        return
    }
    try show()
}
```

Keep `show()` as the ordinary Home/menu action that always opens or refreshes without an implicit navigation step.

- [ ] In `AppRuntime`, route only the global Change Mode hotkey callback to `handleChangeModeShortcut()`. Keep Home and menu-bar actions wired to `show()`.

- [ ] Add the shortcut hint before the existing hints in `ModeSwitcherView`:

```swift
shortcutHint("⌃⌘M", "Next")
shortcutHint("↑↓", "Navigate")
shortcutHint("↩", "Activate")
shortcutHint("esc", "Close")
```

- [ ] Add UI coverage that opens the switcher with the physical configured shortcut, repeats it to select the next of the three built-ins, uses Return to activate, and verifies Escape closes without activation. Also assert the footer exposes `Next`, `Navigate`, `Activate`, and `Close`.

- [ ] Run focused tests:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/ModeSwitcherModelTests \
  -only-testing:WhisperTests/OverlayLifecycleTests \
  -only-testing:WhisperTests/ModesModelTests \
  -only-testing:WhisperUITests/ModeSwitcherUITests \
  -only-testing:WhisperUITests/ModesUITests
```

Expected: first-open, repeated-cycle, wrap, filter, arrow, Return, Escape, row selection, circle activation, menu contents, and detail activation tests all pass.

## Task 6: Full accessibility/manual verification and closure

**Files:**

- Modify: `docs/testing/release-acceptance.md`
- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `README.md` if the shortcut/control description is documented there

- [ ] Run:

```bash
./scripts/verify.sh
git diff --check
```

- [ ] In `build/Whisper.app`, complete a keyboard-only smoke:

  1. Focus another app and press Control-Command-M once; confirm the switcher opens on the active mode.
  2. Repeat the same shortcut through all three built-ins and confirm wraparound.
  3. Confirm Up/Down still navigate, Return activates, and Escape closes/restores the previous app.
  4. Open from Home/menu and confirm it does not move past the active mode on open.
  5. In Modes, click a circle to activate, click row content to inspect, confirm ellipsis has no Activate, and activate from the right detail panel.

- [ ] With VoiceOver, confirm each activation circle announces `Activate <mode name>` plus Active/Inactive, the selected row announces selection separately, and no state relies only on green color.

- [ ] Update UI acceptance rows `U-07` and `U-08` with the tested package commit and sanitized results.

- [ ] Mark `WH-M6-011` `done` only after automated, keyboard, and VoiceOver checks pass. `WH-M6-003` can then resume once `WH-M6-008` through `WH-M6-011` are all done.

- [ ] Commit:

```text
feat(modes): streamline mode switching

- activate modes directly from the list selector
- cycle the open switcher with the global shortcut
```

- [ ] Run the required account/remote/branch/status guard, push `master`, and verify the final commit is present on `origin/master`.
