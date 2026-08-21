# Milestone 1: Native foundation

## WH-M1-001

- **Title:** Scaffold reproducible macOS application
- **Type:** build
- **Status:** done
- **Priority:** P0
- **Scope:** Create XcodeGen manifest, macOS application/test targets, Info.plist, ad-hoc entitlements, app entry, baseline design tokens, bootstrap script, and smoke test.
- **Out of scope:** Product screens beyond a minimal boot surface; feature services.
- **Acceptance criteria:** `Whisper.xcodeproj` is generated reproducibly; app builds for macOS 15+; bundle ID is `dev.yury.whisper`; app is an LSUIElement utility; required usage descriptions exist; smoke test passes.
- **Required checks:** Commands and expected results from implementation plan Task 1.
- **Dependencies:** WH-M0-004.
- **Expected files:** `project.yml`, `Config/**`, `Resources/**`, `Sources/WhisperApp/**`, `Sources/Core/DesignTokens.swift`, `Tests/WhisperTests/SmokeTests.swift`, `scripts/bootstrap.sh`.
- **Source:** implementation plan Task 1.
- **Blockers:** None.

## WH-M1-002

- **Title:** Implement mode, shortcut, and settings domain rules
- **Type:** feature
- **Status:** ready
- **Priority:** P0
- **Scope:** Define modes, default-mode invariants, validated drafts, shortcut values, app settings defaults, retention, result language, and feature errors.
- **Out of scope:** Persistence, UI, hotkey capture, and OpenAI requests.
- **Acceptance criteria:** Default mode cannot be renamed or deleted; names are trimmed and case-insensitively unique; instructions are required; approved shortcut/settings defaults round-trip through Codable.
- **Required checks:** Focused ModeRules and Shortcut tests from implementation plan Task 2; full unit suite.
- **Dependencies:** WH-M1-001.
- **Expected files:** `Sources/Core/ModeDefinition.swift`, `ModeRules.swift`, `AppSettings.swift`, `Shortcut.swift`, `FeatureError.swift`, matching tests.
- **Source:** implementation plan Task 2.
- **Blockers:** None.

## WH-M1-003

- **Title:** Add SwiftData persistence and file layout
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Store mode, dictation, meeting, and transcript metadata; define repositories; create safe Application Support recording and temporary paths; add recovery queries.
- **Out of scope:** Audio capture, network processing, and history UI.
- **Acceptance criteria:** Exactly one default mode is seeded; deleting the active custom mode activates Default; meeting deletion cannot escape its directory; incomplete meetings can be queried after relaunch.
- **Required checks:** Persistence and file-layout tests from implementation plan Task 3.
- **Dependencies:** WH-M1-002.
- **Expected files:** `Sources/Persistence/**`, `Tests/WhisperTests/Persistence/**`.
- **Source:** implementation plan Task 3.
- **Blockers:** WH-M1-002.

## WH-M1-004

- **Title:** Add Keychain, permissions, and launch-at-login services
- **Type:** feature
- **Status:** ready
- **Priority:** P0
- **Scope:** Implement protocol-backed secure storage, OpenAI key lifecycle, permission status/open-settings actions, and launch-at-login state.
- **Out of scope:** Onboarding UI and real OpenAI calls.
- **Acceptance criteria:** API key is never stored in UserDefaults or SwiftData; replace/remove/test consumers use a secure-store protocol; permission queries do not trigger unrelated prompts; launch-at-login failure is recoverable and user-visible.
- **Required checks:** Keychain and permission service tests from implementation plan Task 4; secret-pattern scan.
- **Dependencies:** WH-M1-001.
- **Expected files:** `Sources/Core/SecureStore.swift`, `KeychainSecureStore.swift`, `PermissionService.swift`, `LaunchAtLoginService.swift`, matching tests.
- **Source:** implementation plan Task 4.
- **Blockers:** None.

## WH-M1-005

- **Title:** Review milestone 1 foundation
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Verify build reproducibility, domain invariants, storage safety, secret handling, service boundaries, and readiness for dictation.
- **Out of scope:** Dictation feature implementation.
- **Acceptance criteria:** WH-M1-001..004 are done; complete tests pass; no secret appears outside Keychain abstractions; next task WH-M2-001 becomes ready.
- **Required checks:** Full available Xcode test suite; `git diff --check`; secret scan; clean bootstrap/build on the current Mac.
- **Dependencies:** WH-M1-001, WH-M1-002, WH-M1-003, WH-M1-004.
- **Expected files:** `docs/implementation/reviews/m1-review.md`, backlog updates.
- **Source:** roadmap Milestone 1.
- **Blockers:** Completion of foundation tasks.
