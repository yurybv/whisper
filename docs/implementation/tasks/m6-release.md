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
- **Status:** blocked
- **Priority:** P0
- **Scope:** Execute the manual matrix for target apps, languages, custom mode, permissions, network errors, meeting sources, relaunch recovery, long input, history, and Gatekeeper installation.
- **Out of scope:** Unsupported platforms and post-MVP features.
- **Acceptance criteria:** Every matrix row has pass/fail evidence and version/environment details; failures become scoped follow-up tasks or block release; no private content appears in evidence.
- **Required checks:** All manual cases in `docs/testing/test-strategy.md`.
- **Dependencies:** WH-M6-002.
- **Expected files:** `docs/testing/release-acceptance.md`, sanitized evidence directories.
- **Source:** spec testing strategy and distribution sections.
- **Blockers:** The owner made a foreground session available but limited all interaction to the built-in display. WH-M6-007 resolved the automatic Keychain authorization and startup hang without changing the saved item. The remaining live API, permission, capture, target-app, Gatekeeper, and authorized relaunch rows still require a session in which macOS system dialogs may be handled on whichever display receives them.
- **Acceptance audit (2026-09-15):** Recorded every required dictation, meeting, accessibility, and distribution row against commit `b4f7df0` plus the current acceptance-test hardening diff. Existing production TextEdit and permission/focus evidence is distinguished from current automated coverage; no automated result is represented as a current manual pass. The current package passes the complete verification command, bundle/signature checks, installation to `/Applications`, and the expected ad-hoc Gatekeeper assessment (`spctl` exit 3). Right-click Open launched the quarantined bundle through App Translocation. No API key, private content, or external-display screenshot was collected; the saved Keychain item was not changed.

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
- **Status:** review
- **Priority:** P0
- **Scope:** Separate API-key presence from secret retrieval, make automatic Keychain presence and read queries non-interactive, and allow the packaged app to finish startup when an existing item is inaccessible to the current ad-hoc signature.
- **Out of scope:** Rewriting Keychain ACLs, migrating or deleting the saved key, changing explicit save/remove behavior, Developer ID signing, and completing unrelated live acceptance rows.
- **Acceptance criteria:** Settings can display saved/missing state without retrieving the API key; automatic presence and secret-read queries cannot show authentication UI; an inaccessible item becomes the existing safe Keychain error instead of blocking startup; the API key remains readable only on the first explicit OpenAI operation and cacheable only in process memory; packaged startup completes without a SecurityAgent window or private evidence.
- **Required checks:** Focused `KeychainSecureStoreTests`, `SettingsModelTests`, and `OpenAIClientTests`; `./scripts/verify.sh`; `git diff --check`; no-cursor packaged-startup smoke with sanitized process evidence.
- **Dependencies:** WH-M6-004.
- **Expected files:** `Sources/Core/SecureStore.swift`, `Sources/Core/KeychainSecureStore.swift`, `Sources/UI/Settings/SettingsModel.swift`, `Sources/WhisperApp/AppRuntime.swift`, `Sources/Meetings/MeetingRecoveryService.swift`, focused unit tests, release acceptance evidence, roadmap, and task records.
- **Source:** `docs/superpowers/specs/2026-09-16-whisper-keychain-startup-recovery-design.md` and `docs/superpowers/plans/2026-09-16-whisper-keychain-startup-recovery.md`; follow-up to WH-M6-003 X-07 acceptance failure.
- **Blockers:** None. The repository account guard now returns `yurybv`; the verified commit must be present on `origin/master` before this task moves from `review` to `done`.
- **Implementation (2026-09-16):** Added secret-free API-key presence checks across the secure-store boundary and changed Settings initialization/refresh plus meeting-recovery availability to use them without loading the secret. Meeting recovery no longer checks processing availability when no durable processing job needs it. Automatic Keychain presence and read operations combine a fresh noninteractive `LAContext` with serialized legacy-Keychain interaction suppression, restoring the process setting immediately afterward; explicit save, replace, and remove operations retain their user-initiated behavior. The in-process cache still loads only from an actual OpenAI request and never caches missing, blank, or failed reads.
- **Verification:** TDD covered store presence, cache behavior, Settings no-read initialization/refresh, query construction, temporary legacy-interaction suppression, and the empty meeting-recovery startup path. After review closed the remaining automatic secret-read path, 58 focused Keychain/Settings/OpenAI/meeting tests passed. Full `./scripts/verify.sh` then passed all twelve stages with 301 unit/service tests and 15 UI tests, rebuilt the Release package, and verified its signature. A final no-cursor package launch against the mismatched older item remained alive in the application event loop with zero SecurityAgent windows and no Keychain frame in the sanitized process sample. `git diff --check` remains part of the commit gate; no secret or private content entered evidence.
