# Reliable Warp Text Insertion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generated dictation text paste reliably into Warp without reporting a false `Inserted` result, while retaining direct Accessibility insertion in applications where it works.

**Architecture:** Keep captured-target behavior unchanged. Add a small bundle-identifier policy at the Accessibility insertion boundary; known false-positive applications bypass direct selected-text replacement and use the existing activate, clipboard, Command-V, and clipboard-restore path.

**Tech Stack:** Swift 6.3, AppKit, ApplicationServices, CoreGraphics, XCTest, XcodeGen/Xcodebuild.

**Spec:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md`

## Global Constraints

- Implement only `WH-M6-008`; do not change which application or field is captured when dictation starts.
- Treat `dev.warp.Warp-Stable` as the only paste-preferred bundle until another target is verified.
- Never inspect or log dictated text, clipboard contents, Accessibility values, or user document content.
- Preserve the current clipboard snapshot and manual-paste behavior on every failure path.
- Follow red-green-refactor and run the repository account guard before the final push.

---

## Task 1: Mark the task in progress and add the failing Warp regression

**Files:**

- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `Tests/WhisperTests/Accessibility/TextInsertionServiceTests.swift`

- [ ] Change `WH-M6-008` from `ready` to `in-progress` in both task records. Do not start another implementation task.

- [ ] Add a regression test whose fake Accessibility client returns `.success` for Warp, but which expects the paste path instead of accepting that false success:

```swift
func testWarpSkipsFalsePositiveDirectInsertionAndUsesPasteFallback() async throws {
    let events = EventLog()
    let element = AXUIElementCreateApplication(42)
    let workspace = FakeWorkspaceClient(activationResult: true, events: events)
    let accessibility = FakeAccessibilityClient(
        isTrusted: true,
        setSelectedTextResult: .success,
        events: events
    )
    let pasteboard = FakePasteboardRestorer(
        originalText: "Original clipboard",
        events: events
    )
    let eventPoster = FakePasteEventPoster(postResult: true, events: events)
    let service = makeService(
        workspace: workspace,
        accessibility: accessibility,
        pasteboard: pasteboard,
        eventPoster: eventPoster,
        events: events
    )

    let result = try await service.insert(
        "Generated fixture",
        into: FocusedTarget(
            processIdentifier: 42,
            bundleIdentifier: "dev.warp.Warp-Stable",
            element: element
        )
    )

    XCTAssertEqual(result, .pasted)
    XCTAssertNil(accessibility.insertedText)
    XCTAssertEqual(pasteboard.currentText, "Original clipboard")
    XCTAssertEqual(
        events.values,
        [
            "workspace.activate:42",
            "pasteboard.place",
            "events.postPaste",
            "sleep",
            "pasteboard.restore"
        ]
    )
}
```

- [ ] Run the focused test and confirm it fails because the current implementation calls `setSelectedText` and returns `.insertedDirectly`:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/TextInsertionServiceTests
```

Expected: `testWarpSkipsFalsePositiveDirectInsertionAndUsesPasteFallback` fails; existing insertion tests still compile.

## Task 2: Add a bundle-driven direct-insertion policy

**Files:**

- Modify: `Sources/Accessibility/AXTextInsertionService.swift`
- Modify: `Tests/WhisperTests/Accessibility/TextInsertionServiceTests.swift`

- [ ] Add a value-type policy beside `AXTextInsertionService` and inject it with a production default:

```swift
struct DirectInsertionPolicy: Sendable {
    private let pastePreferredBundleIdentifiers: Set<String>

    init(
        pastePreferredBundleIdentifiers: Set<String> = ["dev.warp.Warp-Stable"]
    ) {
        self.pastePreferredBundleIdentifiers = pastePreferredBundleIdentifiers
    }

    func shouldAttemptDirectInsertion(for target: FocusedTarget) -> Bool {
        guard let bundleIdentifier = target.bundleIdentifier else { return true }
        return !pastePreferredBundleIdentifiers.contains(bundleIdentifier)
    }
}
```

- [ ] Store the policy in `AXTextInsertionService`, expose it as a defaulted initializer argument, and guard only the direct AX branch:

```swift
if directInsertionPolicy.shouldAttemptDirectInsertion(for: target),
   accessibility.isTrusted,
   let element = target.element,
   accessibility.setSelectedText(text, in: element) == .success {
    return .insertedDirectly
}
```

- [ ] Keep the existing paste order exactly: activate captured PID, place text while snapshotting all representations, post Command-V, wait 150 ms, restore the snapshot. If activation or event posting fails, leave generated text on the clipboard and return `.copiedForManualPaste`.

- [ ] Add a focused policy test for an unknown or missing bundle identifier, or rely on the existing `testDirectSelectedTextInsertionIsPreferred` plus the Warp regression if both code paths are explicit and readable.

- [ ] Run the focused test target again:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/TextInsertionServiceTests
```

Expected: all `TextInsertionServiceTests` pass, including direct insertion, Warp paste, clipboard restore, failed activation, and failed paste-event paths.

- [ ] Commit the tested implementation:

```text
fix(accessibility): paste dictation reliably into Warp

- bypass false-positive AX replacement for Warp
- preserve clipboard fallback and direct insertion elsewhere
```

## Task 3: Verify live target behavior and close the task

**Files:**

- Modify: `docs/testing/release-acceptance.md`
- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`

- [ ] Run the complete automated gate:

```bash
./scripts/verify.sh
git diff --check
```

Expected: all verification stages, unit/service tests, UI tests, packaging, and signature checks pass.

- [ ] With `build/Whisper.app`, use generated content only and verify:

  1. Put the insertion point in a Warp terminal prompt, hold/release Push to Talk, and confirm the transformed result appears in that same captured prompt.
  2. Confirm the prior clipboard contents are restored after successful paste.
  3. Repeat in TextEdit and confirm the normal direct-insertion path still works.
  4. Revoke Accessibility temporarily only if the release session already permits permission dialogs; confirm Whisper copies the result and reports manual paste rather than `Inserted`.

- [ ] Update row `D-14` in `docs/testing/release-acceptance.md` with the package commit, Warp bundle identifier, outcome, and sanitized notes. Do not record dictated or pasted content.

- [ ] Mark `WH-M6-008` `done` only after both automated verification and Warp/TextEdit live smoke pass. Update the task record with implementation and verification evidence.

- [ ] Review the final diff, then run the required guard immediately before pushing:

```bash
gh api user --jq .login
git remote get-url origin
git branch --show-current
git status --short
```

Expected: `yurybv`, `https://github.com/yurybv/whisper.git`, `master`, and only the intended task changes.

- [ ] Commit any final evidence/task-record update with a focused documentation commit if it was not included above, push `master`, and verify the final commit is present on `origin/master`.
