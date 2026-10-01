# Milestone 6: Hardening and local release

## WH-M6-001

- **Title:** Add deterministic ad-hoc packaging
- **Type:** build
- **Status:** done
- **Priority:** P0
- **Scope:** Build, archive or assemble, ad-hoc sign, verify, and output a local `Whisper.app` for Apple Silicon with a reproducible script.
- **Out of scope:** Developer ID signing, notarization, App Store packaging, and automatic updates.
- **Acceptance criteria:** Clean checkout produces a launchable app bundle; signature verification passes; output location is deterministic; script refuses unsupported Xcode/SDK/architecture.
- **Required checks:** Packaging and `codesign --verify --deep --strict`; clean-build smoke from implementation plan Task 16.
- **Dependencies:** WH-M5-004.
- **Expected files:** `scripts/package.sh`, build configuration, packaging tests or smoke helpers.
- **Source:** implementation plan Task 16.
- **Blockers:** None.
- **Implementation (2026-09-15):** Added `scripts/package.sh` as the canonical deterministic packaging entry point plus `scripts/package-local.sh` for compatibility with the approved implementation plan. The script refuses non-arm64 hosts, Xcode older than 26.6, SDKs older than macOS 15, missing tools, unexpected or symlinked output roots, wrong bundle identifiers, and non-arm64 executables. It regenerates the Xcode project, removes only the fixed local package outputs, builds an unsigned arm64 Release into `build/DerivedData`, copies exactly `build/Whisper.app`, applies a timestamp-free ad-hoc signature, verifies it deeply and strictly, and prints the absolute result path. Generated package output is ignored by Git.
- **Verification:** Four shell rejection tests passed for unsupported architecture, Xcode, SDK, and a symlinked build root. `scripts/package.sh` completed two independent clean Release builds; both produced byte-identical SHA-256 manifests for every bundle file at the deterministic output path. `build/Whisper.app` reports bundle identifier `dev.yury.whisper`, an arm64-only executable, `Signature=adhoc`, and passes `codesign --verify --deep --strict`. `bash -n` passed; ShellCheck was unavailable. The app was not launched under the owner's no-cursor/no-interference instruction; live packaged-app launch remains part of the later release acceptance matrix.

## WH-M6-002

- **Title:** Add full automated verification command
- **Type:** testing
- **Status:** done
- **Priority:** P0
- **Scope:** Add one script that validates environment, regenerates project, builds, runs unit/UI tests where supported, checks privacy patterns, packages, and verifies the signature.
- **Out of scope:** Network calls to OpenAI and unattended macOS permission UI.
- **Acceptance criteria:** `scripts/verify.sh` fails on any required check; output names each stage; CI-safe checks avoid secrets and external providers; documented exceptions are explicit.
- **Required checks:** Run `scripts/verify.sh` twice from clean generated state; shell lint where available.
- **Dependencies:** WH-M6-001.
- **Expected files:** `scripts/verify.sh`, package/build scripts, test documentation.
- **Source:** implementation plan Task 16 and test strategy.
- **Blockers:** None.
- **Implementation (2026-09-15):** Added `scripts/verify.sh` as the canonical fail-fast entry point. Its twelve named stages validate the supported Mac and toolchain, remove only fixed generated outputs, regenerate the project, run `git diff --check`, reject runtime logging APIs and live OpenAI credential patterns without printing matches, lint every shell script or explicitly fall back to `bash -n`, run shell contract tests, build all test products, run unit and UI targets separately, package the arm64 Release app, and verify its ad-hoc signature. `--skip-ui-tests` is the only optional exception and prints an explicit skip while still compiling the UI-test target.
- **Verification:** `Tests/Scripts/VerifyScriptTests.sh` first failed because `scripts/verify.sh` did not exist, then passed five contract checks covering named stages, unit/UI selection, explicit UI skipping, fail-fast behavior, privacy rejection, and argument validation. `./scripts/verify.sh --skip-ui-tests` passed twice from a freshly removed generated project and verification DerivedData; each run executed 293 unit/service tests with zero failures, produced `build/Whisper.app`, and passed deep strict signature verification. UI execution was explicitly skipped to honor the owner's no-focus/no-cursor-interference instruction; the default path is covered by the shell contract and remains required for final release acceptance. ShellCheck was unavailable, so both runs used the documented `bash -n` fallback.

## WH-M6-003

- **Title:** Run target-app and failure-state acceptance matrix
- **Type:** testing
- **Status:** in-progress
- **Priority:** P0
- **Scope:** Execute the manual matrix for target apps, languages, custom mode, permissions, network errors, meeting sources, relaunch recovery, long input, history, and Gatekeeper installation.
- **Out of scope:** Unsupported platforms and post-MVP features.
- **Acceptance criteria:** Every matrix row has pass/fail evidence and version/environment details; failures become scoped follow-up tasks or block release; no private content appears in evidence.
- **Required checks:** All manual cases in `docs/testing/test-strategy.md`.
- **Dependencies:** WH-M6-002 and WH-M6-008 through WH-M6-013.
- **Expected files:** `docs/testing/release-acceptance.md`, sanitized evidence directories.
- **Source:** spec testing strategy and distribution sections.
- **Blockers:** The initial macOS automation timeout cleared and the full UI suite passed. The owner authorized foreground acceptance and will handle Touch ID when prompted. Physical, real-provider, permission, and recovery rows still require the packaged app's main window and sanitized live checks.
- **Acceptance audit (2026-09-15):** Recorded every required dictation, meeting, accessibility, and distribution row against commit `b4f7df0` plus the current acceptance-test hardening diff. Existing production TextEdit and permission/focus evidence is distinguished from current automated coverage; no automated result is represented as a current manual pass. The current package passes the complete verification command, bundle/signature checks, installation to `/Applications`, and the expected ad-hoc Gatekeeper assessment (`spctl` exit 3). Right-click Open launched the quarantined bundle through App Translocation. No API key, private content, or external-display screenshot was collected; the saved Keychain item was not changed.
- **Acceptance progress (2026-10-01):** The owner authorized the foreground session. The current source passed 322 unit/service tests plus environment, privacy, shell, and build checks. The full gate stopped before its UI tests because macOS timed out while enabling automation; two focused retries reproduced this before any UI test executed, and a process sample located the wait in Local Authentication. A separate clean Release package, strict signature check, bundle/architecture check, and expected unnotarized Gatekeeper assessment passed. A fresh `./scripts/verify.sh --skip-ui-tests` passed all twelve stages for this documentation checkpoint, explicitly without UI execution. The physical and real-provider matrix remains pending; see `docs/testing/release-acceptance.md` and `docs/testing/evidence/WH-M6-003/qa.md`.
- **Acceptance progress (resumed 2026-10-01):** A later focused UI test passed after the initial automation timeout, and the complete `./scripts/verify.sh` passed all twelve stages with 322 unit/service and 17 UI tests, zero failures or skips, clean Release packaging, and strict signature verification. Gatekeeper still rejects the expected unnotarized local package. The manual matrix remains in progress; current results are in `docs/testing/release-acceptance.md` and the sanitized QA note.

## WH-M6-004

- **Title:** Complete privacy, security, and logging review
- **Type:** review
- **Status:** done
- **Priority:** P0
- **Scope:** Review Keychain use, file permissions, path containment, logs, error payloads, Authorization handling, audio lifecycle, deletion, and network request boundaries.
- **Out of scope:** Formal penetration test, compliance certification, and cloud security.
- **Acceptance criteria:** No API key, Authorization header, dictated text, transcript, or instruction is logged; files remain inside the app root; deletion is scoped; all network destinations are expected; findings are fixed or block release.
- **Required checks:** Secret/privacy pattern scan; tests for path containment and redaction; dependency/network review.
- **Dependencies:** WH-M6-002.
- **Expected files:** `docs/implementation/reviews/privacy-security-review.md`, targeted tests/fixes.
- **Source:** spec privacy and error-handling constraints.
- **Blockers:** None.
- **Implementation (2026-09-15):** Audited Keychain storage, in-process key caching, Authorization construction, runtime logging, provider error payloads, app-owned file permissions, relative-path containment, audio lifecycle, tombstone-backed deletion, dependencies, entitlements, and outbound URLSession boundaries. Resolved two findings: OpenAI HTTP error bodies are now discarded before they can reach localized or reflective formatting, and the Application Support audio root, Recordings, Temporary, and meeting directories are verified as real directories and restricted to `0700`. Added provider-payload redaction coverage plus permission and symbolic-link-root regression tests. The numbered severity review is in `docs/implementation/reviews/privacy-security-review.md`.
- **Verification:** Redaction TDD first failed 24 assertions, then 39 selected OpenAI/presentation/processing tests passed. Storage TDD first failed five assertions, then 33 selected persistence/retention/recorder tests passed. `./scripts/verify.sh --skip-ui-tests` passed all twelve stages, executed 295 unit/service tests with zero failures, built both test products, packaged `build/Whisper.app`, and passed deep strict signature verification. Privacy scans found no runtime logging API or live credential pattern in production files; source/dependency review found only the documented OpenAI REST client plus the user-initiated API-key link and no package dependency. UI automation was explicitly skipped to honor the owner's no-focus/no-cursor-interference instruction; foreground release coverage remains isolated in blocked task WH-M6-003.

## WH-M6-005

- **Title:** Write installation and operating runbook
- **Type:** docs
- **Status:** blocked
- **Priority:** P0
- **Scope:** Document build, package, install, right-click Open, permissions, API key, shortcuts, modes, meetings, recovery, storage, deletion, troubleshooting, and uninstall.
- **Out of scope:** Public support site and App Store copy.
- **Acceptance criteria:** A user starting from a clean Mac can install and complete first dictation; privacy/storage boundaries are clear; every common failure points to an exact recovery action.
- **Required checks:** Follow the runbook from a clean packaged build; link check; command copy/paste check.
- **Dependencies:** WH-M6-001, WH-M6-003, WH-M6-004.
- **Expected files:** `README.md`, `docs/operations/troubleshooting.md`, optional `docs/operations/uninstall.md`.
- **Source:** spec distribution section.
- **Blockers:** Completion of packaging and reviews.

## WH-M6-006

- **Title:** Review MVP release readiness
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Final audit of approved scope, automated checks, acceptance matrix, privacy review, packaging, docs, open blockers, and repository/task consistency.
- **Out of scope:** Post-MVP enhancements.
- **Acceptance criteria:** WH-M6-001..005 are done; `scripts/verify.sh` passes; acceptance matrix has no unresolved P0 failure; packaged app installs and runs; every MVP requirement maps to evidence; final status is release-ready or blocked with exact reasons.
- **Required checks:** Full verification, package smoke, account/remote guard, `git diff --check`, backlog completeness audit.
- **Dependencies:** WH-M6-001 through WH-M6-005.
- **Expected files:** `docs/implementation/reviews/m6-release-readiness.md`, final backlog/roadmap updates.
- **Source:** roadmap Milestone 6.
- **Blockers:** Completion of hardening tasks.

## WH-M6-007

- **Title:** Prevent Keychain authorization from blocking startup
- **Type:** bug
- **Status:** done
- **Priority:** P0
- **Scope:** Separate API-key presence from secret retrieval, make automatic Keychain presence and read queries non-interactive, and allow the packaged app to finish startup when an existing item is inaccessible to the current ad-hoc signature.
- **Out of scope:** Rewriting Keychain ACLs, migrating or deleting the saved key, changing explicit save/remove behavior, Developer ID signing, and completing unrelated live acceptance rows.
- **Acceptance criteria:** Settings can display saved/missing state without retrieving the API key; automatic presence and secret-read queries cannot show authentication UI; an inaccessible item becomes the existing safe Keychain error instead of blocking startup; the API key remains readable only on the first explicit OpenAI operation and cacheable only in process memory; packaged startup completes without a SecurityAgent window or private evidence.
- **Required checks:** Focused `KeychainSecureStoreTests`, `SettingsModelTests`, and `OpenAIClientTests`; `./scripts/verify.sh`; `git diff --check`; no-cursor packaged-startup smoke with sanitized process evidence.
- **Dependencies:** WH-M6-004.
- **Expected files:** `Sources/Core/SecureStore.swift`, `Sources/Core/KeychainSecureStore.swift`, `Sources/UI/Settings/SettingsModel.swift`, `Sources/WhisperApp/AppRuntime.swift`, `Sources/Meetings/MeetingRecoveryService.swift`, focused unit tests, release acceptance evidence, roadmap, and task records.
- **Source:** `docs/superpowers/specs/2026-09-16-whisper-keychain-startup-recovery-design.md` and `docs/superpowers/plans/2026-09-16-whisper-keychain-startup-recovery.md`; follow-up to WH-M6-003 X-07 acceptance failure.
- **Blockers:** None.
- **Implementation (2026-09-16):** Added secret-free API-key presence checks across the secure-store boundary and changed Settings initialization/refresh plus meeting-recovery availability to use them without loading the secret. Meeting recovery no longer checks processing availability when no durable processing job needs it. Automatic Keychain presence and read operations combine a fresh noninteractive `LAContext` with serialized legacy-Keychain interaction suppression, restoring the process setting immediately afterward; explicit save, replace, and remove operations retain their user-initiated behavior. The in-process cache still loads only from an actual OpenAI request and never caches missing, blank, or failed reads.
- **Verification:** TDD covered store presence, cache behavior, Settings no-read initialization/refresh, query construction, temporary legacy-interaction suppression, and the empty meeting-recovery startup path. After review closed the remaining automatic secret-read path, 58 focused Keychain/Settings/OpenAI/meeting tests passed. Full `./scripts/verify.sh` then passed all twelve stages with 301 unit/service tests and 15 UI tests, rebuilt the Release package, and verified its signature. A final no-cursor package launch against the mismatched older item remained alive in the application event loop with zero SecurityAgent windows and no Keychain frame in the sanitized process sample. `git diff --check` passed, no secret or private content entered evidence, and verified implementation commit `bccbe65` is present on `origin/master`.

## WH-M6-008

- **Title:** Fix false-positive text insertion in Warp
- **Type:** bug
- **Status:** done
- **Priority:** P0
- **Scope:** Route the known Warp bundle through the existing captured-process clipboard paste strategy so a false-success Accessibility write cannot produce a misleading `Inserted` result.
- **Out of scope:** Changing the captured-target product behavior, replacing Accessibility insertion for working applications, or adding application-specific automatic modes.
- **Acceptance criteria:** A target with bundle identifier `dev.warp.Warp-Stable` skips direct selected-text replacement, activates the captured PID, posts Command-V, restores the prior pasteboard after success, and reports manual paste if activation or event posting fails; direct insertion remains preferred for normal editors; generated text inserted through the production service appears in Warp and TextEdit. The physical generated-dictation journey is part of `WH-M6-003` final acceptance.
- **Required checks:** TDD in `TextInsertionServiceTests`; focused test target; `./scripts/verify.sh`; `git diff --check`; generated-text production-service smoke in Warp and TextEdit.
- **Dependencies:** WH-M6-002, WH-M6-012.
- **Expected files:** `Sources/Accessibility/AXTextInsertionService.swift`, `Tests/WhisperTests/Accessibility/TextInsertionServiceTests.swift`, release acceptance evidence and task records.
- **Source:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md` and `docs/superpowers/plans/2026-09-18-warp-text-insertion.md`; follow-up to WH-M6-003 foreground acceptance.
- **Blockers:** None. The consolidated physical Push-to-Talk and real-provider journey remains assigned to final acceptance task `WH-M6-003`; this task's target-app smoke used fixed synthetic text without reading the saved key or making a provider request.
- **Implementation (2026-09-18):** Added a bundle-specific direct-insertion policy to `AXTextInsertionService`. Captured Warp targets now skip the false-positive selected-text Accessibility write and continue through the existing captured-PID activation, Command-V posting, delayed pasteboard restoration, and manual-paste fallback path. Other targets retain direct Accessibility insertion as the preferred path.
- **Verification:** TDD reproduced Warp returning Accessibility success without receiving text, then passed with a regression test that requires paste fallback, exact event ordering, and restoration of the prior clipboard. On 2026-09-30 the focused insertion suite passed 9 tests. A generated-text smoke compiled the production insertion service into a disposable harness, opened an isolated Warp window through Warp's supported URI, captured bundle `dev.warp.Warp-Stable`, and confirmed the service returned `pasted`, the fixed marker was present in the focused prompt, and every prior pasteboard representation was restored. A separate temporary TextEdit document captured bundle `com.apple.TextEdit` and confirmed `insertedDirectly`, marker presence, and unchanged pasteboard contents. No clipboard value, saved credential, dictated text, or user document content was logged. The same production source at commit `538a294` passed the full `./scripts/verify.sh` gate with 322 unit/service and 17 UI tests before this documentation-only closure. A later UI rerun was interrupted under the owner's no-cursor instruction after a Mattermost window obscured the test app; it is not counted as a pass. Fresh non-UI verification and `git diff --check` were run for the closure; implementation commit `8d2255d` is present on `origin/master`.

## WH-M6-009

- **Title:** Move metadata to a stable app-owned store
- **Type:** bug
- **Status:** done
- **Priority:** P0
- **Scope:** Give SwiftData an explicit store under `Application Support/Whisper/Metadata`, safely adopt a compatible legacy `default.store` before opening the canonical container, and make migration failure visible instead of silently creating empty metadata.
- **Out of scope:** Cloud sync, backup UI, Time Machine integration, deleting the legacy store, or reconstructing records no longer present on disk.
- **Acceptance criteria:** Store location is stable across build paths and relaunches; a compatible synthetic legacy store migrates modes, dictations, meetings, transcript segments, and cleanup tombstones; an existing canonical store always wins; migration is idempotent and non-destructive; failed migration does not open an empty replacement; app-owned metadata directories are `0700`.
- **Required checks:** TDD in `PersistenceTests`; focused persistence, history, recovery, and retention tests; `./scripts/verify.sh`; `git diff --check`; packaged rebuild/relaunch smoke with synthetic records.
- **Dependencies:** WH-M6-002.
- **Expected files:** `Sources/Persistence/AppPaths.swift`, `Sources/Persistence/PersistenceController.swift`, a focused store-location/migration service, `Sources/WhisperApp/AppRuntime.swift`, persistence tests, ADR/README updates, release acceptance evidence and task records.
- **Source:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md` and `docs/superpowers/plans/2026-09-18-persistent-metadata-store.md`; follow-up to WH-M6-003 data-loss finding.
- **Blockers:** None. The already-overwritten production legacy store contains no recoverable history; this historical limitation does not affect prevention or migration of compatible legacy data still present on another installation.
- **Implementation (2026-09-18; review fixes 2026-09-29):** Added the private `Metadata` directory and explicit `Whisper.store` URL, made disk-backed `PersistenceController` construction require an explicit URL, and wired startup through a pre-container relocator. Compatibility now requires the exact current model-version hashes, inspection errors fail closed, and SQLite's online-backup API captures a coherent legacy snapshot with one five-second monotonic deadline and short lock waits. The staged store is count-validated across every Whisper entity, then promoted with atomic non-recursive empty-directory removal; a canonical store concurrently promoted by another launch wins. The legacy source is never deleted, and snapshot, validation, or promotion failure stops startup.
- **Verification:** The focused persistence and snapshot suites pass 29 tests, including every entity type, exact hash rejection, fail-closed metadata inspection, live WAL writes/checkpoints, bounded snapshot timeout, canonical-wins, idempotence, concurrent promotion, populated-directory preservation, injected snapshot failure, permissions, and reopen durability. Independent review reported no remaining critical, important, or minor findings. On 2026-09-29 the canonical `./scripts/verify.sh` passed all twelve stages with 322 unit/service tests and 17 UI tests, rebuilt the Release package, and passed strict signature verification. The sanitized package smoke quarantined the owner stores without reading them, wrote fixed generated mode and dictation IDs into a compatible synthetic legacy store through production repositories, then proved the verified package migrated both IDs and preserved them across a clean repackage/relaunch and exact `/Applications/Whisper.app` relocation. Metadata stayed `0700`, the recordings root stayed app-owned, and the original stores and installed app were restored; disposable synthetic artifacts were moved to Trash. `git diff --check` passes. Implementation commit `cdd92d9` is present on `origin/master`.

## WH-M6-010

- **Title:** Seed protected Russian-to-English built-in modes
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Add the owner-provided Work / Technical and Slack / Friendly presets as stable protected built-ins, seed them idempotently beside Default, and preserve existing user modes and active selection.
- **Out of scope:** A downloadable mode library, editing built-in instructions, app-specific activation, or changing meeting-recording instructions.
- **Acceptance criteria:** Fresh and upgraded stores expose exactly three canonical built-ins in deterministic order; repeated launch creates no duplicates; built-ins cannot be edited, renamed, or deleted but can be duplicated; exact owner instructions and Russian language hints are used; collisions preserve the custom mode under a deterministic custom suffix; existing active modes remain active.
- **Required checks:** TDD in mode-rule, persistence, model, and UI tests; focused test targets; `./scripts/verify.sh`; `git diff --check`; packaged fresh/relaunch smoke.
- **Dependencies:** WH-M6-009.
- **Expected files:** `Sources/Core/ModeDefinition.swift`, `Sources/Persistence/ModeRepository.swift`, Modes models/views, UI-test fixtures, focused tests, README and task records.
- **Source:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md` and `docs/superpowers/plans/2026-09-18-built-in-modes-and-switching.md`.
- **Blockers:** None. `WH-M6-009` is complete. Foreground and packaged visual confirmation is consolidated under final acceptance task `WH-M6-003` per the owner's no-screen-touching instruction.
- **Implementation (2026-09-18):** Added the two owner-supplied Russian-to-English presets with stable IDs, exact instructions, Russian input hints, deterministic ordering, and built-in identity protection. Startup now reconciles all three canonical modes, repairs stale canonical rows, preserves custom content and active selection, and deterministically renames exact-name custom collisions before inserting a preset. Modes UI treats every built-in as protected while keeping duplication available.
- **Verification:** TDD first exposed missing built-in constants, default-only reconciliation, and editable non-default presets. On 2026-09-29 the screen-safe focused mode-rule, persistence, and Modes-model selection passed 42 tests with zero failures; no foreground app or UI-test target was launched. A deterministic UI test covers all three names, protected instructions, and duplication, and the previously completed full gate passed 322 unit/service tests plus 17 UI tests against the same implementation. Fresh/upgraded packaged visual confirmation is explicitly assigned to consolidated final acceptance task `WH-M6-003`. `git diff --check` passes, and implementation commit `6621082` is present on `origin/master`.

## WH-M6-011

- **Title:** Improve mode activation and shortcut cycling
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Make the Modes-list circle activate its mode, remove Activate from the ellipsis menu while retaining the detail action, and let repeated Control-Command-M presses advance the open switcher selection with explicit footer guidance.
- **Out of scope:** Automatically activating on selection movement, changing configurable shortcut recording, removing arrow navigation, or adding app-specific mode activation.
- **Acceptance criteria:** The circle is a labeled 44-point activation control; row selection still opens details; ellipsis contains no Activate action; the right detail action remains; first Control-Command-M opens with active selection and repeated presses advance/wrap; arrows, Return, Escape, focus restoration, filtering, and menu/Home opening retain their existing behavior; footer documents all controls.
- **Required checks:** TDD in `ModesModelTests`, `ModeSwitcherModelTests`, controller/lifecycle tests, and UI tests; `./scripts/verify.sh`; `git diff --check`; keyboard-only and VoiceOver packaged smoke.
- **Dependencies:** WH-M6-010.
- **Expected files:** `Sources/UI/Modes/ModesListView.swift`, `Sources/UI/ModeSwitcher/*`, `Sources/WhisperApp/AppRuntime.swift`, focused unit/UI tests, release acceptance evidence and task records.
- **Source:** `docs/superpowers/specs/2026-09-18-release-stabilization-design.md` and `docs/superpowers/plans/2026-09-18-built-in-modes-and-switching.md`.
- **Blockers:** None. `WH-M6-010` is complete. Physical shortcut, VoiceOver, and packaged UI checks are consolidated under final acceptance task `WH-M6-003` per the owner's no-screen-touching instruction.
- **Implementation (2026-09-19):** Split the Modes row into a dedicated labeled 44-point activation circle, an inspection row, and a task-focused ellipsis menu without Activate. The global shortcut now opens once and advances the existing switcher selection on repeats, while Home/menu presentation still opens on the active mode. Added the `⌃⌘M Next` footer hint and retained arrows, Return, Escape, filtering, and focus restoration.
- **Verification:** TDD added repeat/wrap/filter model coverage and a controller lifecycle regression proving one presentation, no rebuild on repeats, activation, close, and focus restoration. On 2026-09-29 a screen-safe selection passed 15 pure/model/fake-controller/hotkey tests with zero failures; tests that instantiate or present real panels were intentionally excluded. Source review confirms a separate labeled 44-point activation button, inspection-only row button, no Activate menu item, retained detail activation, shortcut-only cycling, and all four footer hints. The previously completed full gate passed 322 unit/service tests plus 17 UI tests against the same implementation. Physical shortcut, VoiceOver, focus, and packaged UI confirmation are explicitly assigned to consolidated final acceptance task `WH-M6-003`. `git diff --check` passes, and implementation commit `8750c44` is present on `origin/master`.

## WH-M6-012

- **Title:** Auto-dismiss terminal dictation HUD errors
- **Type:** bug
- **Status:** done
- **Priority:** P0
- **Scope:** Give terminal dictation failures a readable bounded HUD lifetime so a Keychain or provider error cannot cover target applications indefinitely while preserving the failed session and its menu-bar Retry/Discard actions.
- **Out of scope:** Automatically retrying or discarding captured audio, changing Keychain access policy, changing failure copy, or altering active recording/processing HUD lifetime.
- **Acceptance criteria:** Failed dictation HUDs dismiss automatically after a readable delay; completed and cancelled timing remains unchanged; active recording, transcribing, transforming, and inserting HUDs remain visible; recoverable audio and menu-bar Retry/Discard state remain intact; saving or replacing the API key updates the existing in-process cache and Retry can use it without relaunching.
- **Required checks:** TDD in `OverlayLifecycleTests`; focused overlay, secure-store, recovery-router, and dictation tests; `./scripts/verify.sh`; `git diff --check`; packaged missing-key → save-key → Retry smoke without retaining dictated or secret content.
- **Dependencies:** WH-M6-007.
- **Expected files:** `Sources/UI/HUD/DictationHUDController.swift`, `Tests/WhisperTests/UI/OverlayLifecycleTests.swift`, release acceptance evidence and task records.
- **Source:** approved MVP state-machine, error-handling, and nonactivating-HUD sections in `docs/superpowers/specs/2026-08-19-whisper-macos-mvp-design.md`; follow-up to WH-M6-008 live verification.
- **Blockers:** None. The credential-dependent packaged missing-key → save-key → Retry journey is consolidated under final acceptance task `WH-M6-003`, where the owner's saved key can remain masked and untouched by component-level verification.
- **Implementation (2026-09-18):** Terminal dictation failures now keep the nonactivating HUD visible for four seconds and then hide it. Dismissal only affects the panel; the coordinator retains recoverable audio and the menu bar continues to expose Retry/Discard. Saving or replacing the key continues to update the shared `CachingSecureStore`, so Retry uses the new value without relaunching.
- **Verification:** TDD first reproduced the failure with the error panel still visible after 4.25 seconds, then passed after adding the bounded error lifetime. On 2026-09-29, and again after the Mac reboot on 2026-09-30, the focused overlay, Keychain/cache, recovery-router, and dictation selection passed 32 tests with zero failures; the latest real lifecycle elapsed 4.429 seconds. A computer-vision pass observed the real nonactivating `Dictation failed` panel with synthetic, secret-free copy while it was visible and confirmed the test host disappeared after the four-second timeout. On 2026-09-21 the full `./scripts/verify.sh` passed all twelve stages with 316 unit/service tests and 17 UI tests, and the later 2026-09-29 full gate passed 322 unit/service tests plus 17 UI tests against the same implementation before packaging and strict signature verification. The credential-dependent packaged Retry journey remains explicitly assigned to consolidated final acceptance task `WH-M6-003`; component verification did not read, replace, or expose the owner's saved key. `git diff --check` passes, and implementation commit `3360ab6` is present on `origin/master`.

## WH-M6-013

- **Title:** Preserve macOS permissions with a stable local signing identity
- **Type:** build
- **Status:** done
- **Priority:** P0
- **Scope:** Create one free, persistent Code Signing identity in the owner's login Keychain, require it for every Release package, and document the one-time migration from ad-hoc builds.
- **Out of scope:** Developer ID, notarization, App Store delivery, TCC database changes, and exporting or publishing the private key.
- **Acceptance criteria:** Setup reuses exactly one valid identity and refuses conflicting state; packaging fails before changing output if that identity is absent or ambiguous; two clean packages have the same signing authority and designated requirement; strict signature verification and full repository checks pass; no private-key material enters Git.
- **Required checks:** TDD shell tests for identity resolution and packaging rejection; `./scripts/package.sh` twice; `./scripts/verify.sh`; `git diff --check`; owner check that permissions persist after one migration and rebuild.
- **Dependencies:** WH-M6-002.
- **Expected files:** `scripts/setup-local-signing.sh`, `scripts/local-signing-identity.sh`, `scripts/package.sh`, shell tests, ADR, README, roadmap, test strategy, release acceptance, task records.
- **Source:** `docs/superpowers/specs/2026-09-22-stable-local-code-signing-design.md` and `docs/superpowers/plans/2026-09-22-stable-local-code-signing.md`; explicit owner request for free persistent signing.
- **Blockers:** None.
- **Implementation (2026-09-22):** Added an idempotent local-identity setup command and an exact login-Keychain fingerprint resolver. Provisioned a ten-year self-signed Code Signing certificate with a non-extractable private key, Code Signing trust, and `/usr/bin/codesign` access. Packaging now refuses a missing or ambiguous identity before touching the previous bundle, signs only with the persistent fingerprint, and verifies both the expected authority and certificate-bound designated requirement without an ad-hoc fallback. Updated the signing decision, distribution guidance, and manual acceptance matrix.
- **Verification:** Resolver/setup and packaging rejection tests passed, including an initially failing missing-identity and missing-setup TDD pass. On 2026-09-30, after a Mac reboot, two independent clean Release builds signed `build/Whisper.app` with the same certificate SHA-1 `3918F34830AA1C4307777059BC515CCB72620601`, the same `dev.yury.whisper` identifier, the same `Whisper Local Development` authority, the same CDHash, and the same certificate-bound designated requirement; both passed deep strict `codesign` verification without another Keychain prompt. The exact second package launched from `build/Whisper.app`, and read-only inspection of System Settings confirmed that Microphone, Accessibility, Input Monitoring, and Screen & System Audio Recording all remained enabled after the reboot and both rebuilds. A fresh full `./scripts/verify.sh` then passed all twelve stages with 322 unit/service tests and 17 UI tests, rebuilt the Release package, and passed strict signature verification. `git diff --check` passes. No permission switch, saved credential, private key, or TCC database was changed during acceptance.
