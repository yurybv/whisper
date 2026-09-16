# Whisper Keychain Startup Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkboxes so recovery can resume at the first incomplete step.

**Goal:** Prevent an inaccessible existing Keychain item from blocking app startup or showing an automatic authorization dialog, while preserving Keychain-only secret storage and reading the secret only for an explicit OpenAI operation.

**Architecture:** Split secret presence from secret retrieval in `SecureStore`. Settings performs an attributes-only, non-interactive presence query; OpenAI operations retain the existing cached secret read, also made non-interactive. Explicit save, replace, and remove actions keep their current user-initiated Keychain behavior.

**Tech Stack:** Swift 6, Security.framework, LocalAuthentication.framework, XCTest, SwiftUI, XcodeGen, shell verification scripts.

**Global Constraints:** Do not expose, migrate, rewrite ACLs for, or delete the existing API key. Do not use cursor/UI automation or interact with the external display. Do not push until the `yurybv` account guard passes. Keep the follow-up task in `review` until its verified commit is present on `origin/master`.

---

### Task 1: Add a non-interactive Keychain presence boundary

**Files:**
- Modify: `Sources/Core/SecureStore.swift`
- Modify: `Sources/Core/KeychainSecureStore.swift`
- Test: `Tests/WhisperTests/Core/KeychainSecureStoreTests.swift`
- Modify: `Tests/WhisperTests/UI/SettingsModelTests.swift` (protocol fake only)
- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`

- [x] **Step 1: Record the scoped follow-up**

Add `WH-M6-007` to the Milestone 6 task record and backlog as `in-progress`. Scope it to non-interactive Keychain presence/read behavior and startup recovery. Make it depend on `WH-M6-004`, and identify it as the follow-up that must unblock `WH-M6-003`.

- [x] **Step 2: Write failing presence tests**

Add tests that require every `SecureStore` to report whether a nonempty key exists, verify the in-memory lifecycle, verify `CachingSecureStore` delegates presence without loading a secret into its cache, and verify a cached nonempty key satisfies presence without another backing-store call.

Add query-construction assertions for `KeychainSecureStore`:

```swift
let presenceQuery = store.presenceQuery
XCTAssertEqual(presenceQuery[kSecReturnAttributes] as? Bool, true)
XCTAssertNil(presenceQuery[kSecReturnData])
XCTAssertEqual(
    (presenceQuery[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed,
    true
)
```

Make the equivalent authentication-context assertion for the secret-read query.

- [x] **Step 3: Run the focused test and confirm the expected failure**

Run:

```bash
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' -derivedDataPath build/KeychainRecoveryDerivedData test -only-testing:WhisperTests/KeychainSecureStoreTests
```

Expected: compilation or assertion failure because the presence API and non-interactive queries do not exist yet.

- [x] **Step 4: Implement the smallest passing store change**

Add this protocol operation:

```swift
func containsOpenAIKey() throws -> Bool
```

Implement it in `InMemorySecureStore`, `CachingSecureStore`, and test fakes. In `CachingSecureStore`, return `true` for a cached nonempty key; otherwise delegate without calling `readOpenAIKey()` and without populating `cachedKey`.

In `KeychainSecureStore`, import `LocalAuthentication`, create a fresh `LAContext` with `interactionNotAllowed = true` for each presence/read query, and expose internal query builders for `@testable` assertions. Presence must request attributes only and map `errSecSuccess` to `true`, `errSecItemNotFound` to `false`, and every other result to `FeatureError.keychain`. Secret reads keep returning data but use the same non-interactive authentication context. Do not change save/delete behavior.

- [x] **Step 5: Run focused tests**

Run the command from Step 3. Expected: `KeychainSecureStoreTests` passes.

### Task 2: Stop Settings from retrieving the API key

**Files:**
- Modify: `Sources/UI/Settings/SettingsModel.swift`
- Test: `Tests/WhisperTests/UI/SettingsModelTests.swift`

- [x] **Step 1: Write failing Settings tests**

Add a tracking secure store and assert that `SettingsModel` initialization and `refresh()` call `containsOpenAIKey()` but never call `readOpenAIKey()`. Cover both saved and missing states. Keep the safe Keychain-error presentation test, but drive it through a presence-query failure.

- [x] **Step 2: Run the focused test and confirm the expected failure**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' -derivedDataPath build/KeychainRecoveryDerivedData test -only-testing:WhisperTests/SettingsModelTests
```

Expected: the new read-count assertion fails because Settings still calls `readOpenAIKey()`.

- [x] **Step 3: Implement presence-only Settings state**

Replace both Settings startup and refresh secret reads with `containsOpenAIKey()`. Preserve `.saved`/`.missing` transitions, `.connected` handling, and the current safe error message. Keep the actual secret read exclusively on the existing OpenAI request path.

- [x] **Step 4: Run focused regression tests**

Run:

```bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination 'platform=macOS' -derivedDataPath build/KeychainRecoveryDerivedData test \
  -only-testing:WhisperTests/SettingsModelTests \
  -only-testing:WhisperTests/KeychainSecureStoreTests \
  -only-testing:WhisperTests/OpenAIClientTests
```

Expected: all selected tests pass, including proof that OpenAI still reads the secret only when making a request.

- [x] **Step 5: Remove the remaining meeting-recovery availability read**

Use `containsOpenAIKey()` for meeting-recovery availability and do not check availability at all when there is no captured, transcribing, or processing job to resume. Add a regression test proving an empty startup recovery does not invoke the availability closure.

### Task 3: Verify packaged startup and record evidence

**Files:**
- Modify: `docs/testing/release-acceptance.md`
- Modify: `docs/implementation/roadmap.md`
- Modify: `docs/implementation/tasks/m6-release.md`
- Modify: `docs/implementation/task-backlog.md`
- Verify: `build/Whisper.app`

- [x] **Step 1: Run repository verification**

Run:

```bash
./scripts/verify.sh
git diff --check
```

Expected: all unit/service and UI tests pass, Release packaging completes, and the ad-hoc signature verifies.

- [x] **Step 2: Run a no-cursor packaged-startup smoke**

Start `build/Whisper.app/Contents/MacOS/Whisper` directly from the shell without changing onboarding preferences, moving windows, or using UI automation. Capture only process state and sanitized stack/window metadata. Assert within a short bounded interval that:

- the process remains alive and completes `AppRuntime` initialization;
- its main thread is not blocked in `SecItemCopyMatching`;
- no `SecurityAgent` authorization window appears;
- no key value, transcript, dictated text, Authorization header, or private content enters the evidence.

Terminate only the exact smoke-test PID after the assertions. Do not modify or delete the Keychain item.

- [x] **Step 3: Update release evidence and task state**

Document the startup recovery under X-07. Narrow the `WH-M6-003` blocker to the remaining live acceptance rows; do not represent the no-cursor smoke as a full manual pass. Update the roadmap. Set `WH-M6-007` to `review`, because verification is complete locally but the account guard and required push are deliberately deferred.

- [ ] **Step 4: Review and deliver a focused commit**

Inspect:

```bash
git status --short
git diff --stat
git diff --check
git diff -- Sources/Core Sources/UI Tests docs
```

Create one local Conventional Commit:

```text
fix(keychain): avoid authorization prompt at startup

- query API-key presence without retrieving the secret
- disable authentication UI for automatic Keychain reads
- record packaged startup verification and release follow-up state
```

Run the repository account guard immediately before pushing. The owner authorized switching to `yurybv` on 2026-09-16; if the guard returns the required account, HTTPS remote, and `master` branch, push directly to `master`, then change `WH-M6-007` from `review` to `done` in a follow-up documentation commit.
