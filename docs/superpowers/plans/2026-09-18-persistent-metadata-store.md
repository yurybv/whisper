# Stable App-Owned Metadata Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist modes, dictation history, meetings, transcript segments, and cleanup tombstones at a stable Whisper-owned URL and safely adopt any compatible legacy `default.store` without risking silent data loss.

**Architecture:** `AppPaths` owns the canonical metadata directory and URL. A pre-container relocation service examines only persistent-store metadata, stages a copy of a compatible SQLite family, atomically promotes it, and leaves the legacy files untouched. `AppRuntime` must resolve this URL before creating SwiftData; any compatible-store migration failure aborts startup instead of falling through to an empty store.

**Tech Stack:** Swift 6.3, Foundation, SwiftData, Core Data persistent-store metadata APIs, XCTest, XcodeGen/Xcodebuild.

**Spec:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md`

## Global Constraints

- Implement only `WH-M6-009`; do not seed the two new presets in this task.
- Canonical store URL is exactly `~/Library/Application Support/Whisper/Metadata/Whisper.store` in production.
- Never open, mutate, delete, or log contents from the owner's production legacy store during tests.
- Canonical data always wins. Legacy adoption is attempted only when the canonical store family is absent.
- A compatible legacy-store copy failure must be surfaced; it must never lead to a new empty canonical database.
- Keep legacy files untouched after successful migration so manual rollback remains possible.
- Follow red-green-refactor and run the repository account guard before the final push.

---

## Task 1: Define the canonical paths with permission tests

**Files:**

- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Modify: `Sources/Persistence/AppPaths.swift`
- Modify: `Tests/WhisperTests/Persistence/PersistenceTests.swift`

- [ ] Change `WH-M6-009` from `ready` to `in-progress` in both task records.

- [ ] Add failing assertions to `testCreatesApplicationSupportLayoutUnderInjectedRoot`:

```swift
XCTAssertEqual(
    paths.metadataDirectoryURL,
    root.appendingPathComponent("Metadata", isDirectory: true)
)
XCTAssertEqual(
    paths.metadataStoreURL,
    root.appendingPathComponent("Metadata", isDirectory: true)
        .appendingPathComponent("Whisper.store")
)
XCTAssertTrue(FileManager.default.fileExists(atPath: paths.metadataDirectoryURL.path))
```

Add `paths.metadataDirectoryURL` to the existing `0700` permission loop.

- [ ] Run the focused persistence test and confirm it fails to compile because those paths do not yet exist:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/PersistenceTests/testCreatesApplicationSupportLayoutUnderInjectedRoot
```

- [ ] Extend `AppPaths` with immutable `metadataDirectoryURL` and `metadataStoreURL`. Create and permission the metadata directory using the existing symlink-safe private-directory helper.

- [ ] Re-run the focused test and confirm it passes.

## Task 2: Build and test a non-destructive store relocator

**Files:**

- Create: `Sources/Persistence/PersistentStoreRelocator.swift`
- Modify: `Sources/Persistence/PersistenceController.swift`
- Modify: `Tests/WhisperTests/Persistence/PersistenceTests.swift`

- [ ] Add a synthetic-store test fixture that creates `default.store` under a temporary fake Application Support root through `PersistenceController(storeURL:)`, then inserts deterministic synthetic records for all five entities through production repositories/context:

  - one custom `ModeEntity` with a known UUID;
  - one `DictationEntity` with generated fixture text;
  - one `MeetingEntity` with generated metadata;
  - one `TranscriptSegmentEntity` attached to that meeting;
  - one `RecordingCleanupEntity` with a safe synthetic relative path.

Record only IDs/counts in assertions; never use production data.

- [ ] Add failing tests for this contract:

```swift
@MainActor
func testRelocatorCopiesCompatibleLegacyStoreAndPreservesEveryEntity() throws

func testRelocatorUsesExistingCanonicalStoreWithoutTouchingLegacy() throws

func testRelocatorIsIdempotentAfterSuccessfulPromotion() throws

func testRelocatorIgnoresUnrelatedLegacyStore() throws

func testRelocatorLeavesLegacyUntouchedAndNoCanonicalStoreWhenCopyFails() throws
```

The first test must reopen `paths.metadataStoreURL` and compare the seeded IDs/counts for modes, dictations, meetings, segments, and tombstones. The canonical-wins test must seed distinct IDs in both stores and prove only canonical IDs are returned. The failure test must inject a file operation that fails after compatibility detection and assert that `default.store` still exists and `Metadata/Whisper.store` does not.

- [ ] Run the focused tests and confirm the migration cases fail before the service exists:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/PersistenceTests
```

- [ ] Implement a narrow `PersistentStoreRelocating` boundary and production `PersistentStoreRelocator`. Its public operation should return the canonical URL or throw:

```swift
protocol PersistentStoreRelocating: Sendable {
    func prepareCanonicalStore(
        paths: AppPaths,
        legacyStoreURL: URL
    ) throws -> URL
}
```

- [ ] Determine compatibility without fetching user objects. Use `NSPersistentStoreCoordinator.metadataForPersistentStore(ofType:at:)` and require the model-version hashes for the complete Whisper schema (`ModeEntity`, `DictationEntity`, `MeetingEntity`, `TranscriptSegmentEntity`, and `RecordingCleanupEntity`) to match the current model. Keep metadata inspection in a focused helper so tests can inject compatible, incompatible, and throwing results.

- [ ] Copy the complete SQLite family. For base URL `default.store`, copy the base plus existing `default.store-wal` and `default.store-shm` to a unique staging directory under `AppPaths.rootURL`, renaming the destination family to `Whisper.store`, `Whisper.store-wal`, and `Whisper.store-shm`.

- [ ] Promote atomically at the directory level:

  1. Recheck that `Metadata/Whisper.store` is absent.
  2. Validate the staged store by opening a temporary `PersistenceController(storeURL:)` and fetching only entity counts/IDs.
  3. Remove only the empty newly-created `Metadata` directory, if present.
  4. Move the staging directory to `Metadata` in the same Application Support volume.
  5. On error, remove only the unique staging directory and rethrow; never remove the legacy family.

- [ ] Avoid a race between two launches by treating an already-present canonical store discovered during the final recheck as success and discarding only the staging copy.

- [ ] Add a `PersistenceError` case with a user-safe localized description for an incompatible or failed local-store migration if the existing startup error surface requires it. The error and diagnostics may include the migration stage but not stored content.

- [ ] Run all persistence tests and confirm every relocation, reopen, permission, history, recovery, and cleanup test passes.

## Task 3: Wire the explicit store URL into production startup

**Files:**

- Modify: `Sources/Persistence/PersistenceController.swift`
- Modify: `Sources/WhisperApp/AppRuntime.swift`
- Modify: `Tests/WhisperTests/Persistence/PersistenceTests.swift`

- [ ] Add a failing reopen test that creates `PersistenceController(storeURL: paths.metadataStoreURL)`, writes synthetic data, releases the container, reopens the same URL, and verifies the same IDs are present.

- [ ] Make production persistence explicit. Preserve `PersistenceController(inMemory: true)` for unit tests, but do not allow the normal app path to construct an implicit default SwiftData store. A safe shape is:

```swift
init(inMemory: Bool = false, storeURL: URL? = nil) throws {
    // In-memory tests remain supported.
    // Every disk-backed production call must provide storeURL.
}
```

If retaining an optional parameter, precondition or throw when both `inMemory == false` and `storeURL == nil`; update every disk-backed call site.

- [ ] In `AppRuntime.init()`, use this order before creating repositories:

```swift
let paths = try AppPaths()
let applicationSupport = paths.rootURL.deletingLastPathComponent()
let legacyStoreURL = applicationSupport.appendingPathComponent("default.store")
let storeURL = try PersistentStoreRelocator().prepareCanonicalStore(
    paths: paths,
    legacyStoreURL: legacyStoreURL
)
persistence = try PersistenceController(storeURL: storeURL)
```

Do not catch and replace relocation/container errors with a second empty container.

- [ ] Run the full focused persistence suite again:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test \
  -only-testing:WhisperTests/PersistenceTests
```

- [ ] Commit the tested implementation:

```text
fix(persistence): stabilize local metadata storage

- use an explicit app-owned SwiftData store
- adopt compatible legacy metadata non-destructively
```

## Task 4: Document, package, and prove relaunch durability

**Files:**

- Modify: `README.md`
- Modify: `docs/architecture/adr/0003-separate-metadata-and-audio-storage.md`
- Modify: `docs/testing/release-acceptance.md`
- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`

- [ ] Update the README and ADR with the canonical metadata URL, the separate recordings URL, the one-time compatible legacy adoption rule, canonical-wins behavior, legacy retention, and the fact that this is local storage rather than cloud backup.

- [ ] Run the full automated gate:

```bash
./scripts/verify.sh
git diff --check
```

Expected: all verification stages and packaging/signature checks pass.

- [ ] Perform a sanitized package smoke without using the owner's missing records:

  1. Back up any existing canonical and legacy store families outside the active paths before changing test state.
  2. Launch the verified package and create one synthetic custom mode and one generated dictation record.
  3. Quit completely, rebuild/repackage, and launch from `build/Whisper.app`; confirm both records remain.
  4. Copy the exact verified bundle to `/Applications`, launch it, and confirm the same records remain.
  5. Confirm the metadata directory is `0700` and the app still resolves recordings under `Application Support/Whisper/Recordings`.
  6. Restore any backed-up store families after the smoke. Never copy private content into evidence.

- [ ] Update distribution row `X-08` in release acceptance with the tested commit and sanitized count/ID outcome. State separately that the previously observed history cannot be recovered from the current legacy store because it already contains zero history records.

- [ ] Mark `WH-M6-009` `done` only after automated verification and rebuilt/relocated launch smokes pass. This unblocks `WH-M6-010`.

- [ ] Run the account/remote/branch/status guard immediately before pushing:

```bash
gh api user --jq .login
git remote get-url origin
git branch --show-current
git status --short
```

Expected: `yurybv`, `https://github.com/yurybv/whisper.git`, `master`, and only intended files.

- [ ] Commit any final evidence/task update if needed, push `master`, and verify the final task commit is present on `origin/master`.
