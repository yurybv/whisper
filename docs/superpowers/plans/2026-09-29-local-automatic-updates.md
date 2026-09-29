# Local Automatic Updates Implementation Plan

> **For agentic workers:** Follow the repository task workflow and implement one task at a time with TDD. This document is a plan, not implementation authorization. Complete Milestone 6's review gate before selecting Milestone 7. This plan is the linked detail for the Milestone 7 task records.

**Goal:** Publish `v1.0.0` from the owner's Mac, then let the installed Whisper app update to `v1.0.1` and later patch releases without manual rebuilding or reinstalling.

**Architecture:** Sparkle 2 reads a stable `releases/latest/download/appcast.xml` URL. A local guarded release command derives versions from Git tags, injects bundle metadata before signing, creates a ZIP plus appcast containing its EdDSA signature, and publishes them together as a GitHub Release. The existing non-extractable signing identity remains local.

**Tech Stack:** Swift 6/SwiftUI, Sparkle 2, XcodeGen, Bash, macOS `codesign`/`ditto`/Keychain, GitHub CLI and Releases.

**Design:** [Local Automatic Updates Design](../specs/2026-09-29-local-automatic-updates-design.md).

## Global constraints and sequencing

- The planning checkpoint may be committed locally as documentation. It does not authorize an app build, signing-key creation, GitHub account switch, push, tag, or release.
- `WH-M6-006` must be `done` before Milestone 7 implementation begins. Existing `review` and `blocked` M6 tasks remain untouched by this plan.
- Before every future remote write, enforce `gh api user --jq .login == yurybv`, `origin == https://github.com/yurybv/whisper.git`, and `branch == master`; the script must fail before any write otherwise.
- Preserve `dev.yury.whisper`, the current persistent local signing identity, app storage, Keychain access, and macOS consent boundaries. Do not delete TCC entries or user data.
- Do not store signing keys, OpenAI keys, dictated text, recordings, transcripts, or Authorization headers in Git, artifacts, logs, or test evidence.
- TDD first for behavior and script contracts. Run focused tests before the full `./scripts/verify.sh` gate. UI and installation QA use only the built-in display.
- Do not mark any future task `done` until its acceptance checks pass and its verified commit reaches `origin/master`; a local planning commit cannot satisfy that condition.

## Task 1 — Version metadata and package integrity (`WH-M7-001`)

**Files:** `Resources/Info.plist`, `Sources/UI/Settings/SettingsView.swift`, a small bundle-version formatter/model under `Sources/Core/`, `scripts/package.sh`, `Tests/Scripts/PackageScriptTests.sh`, focused Swift tests under `Tests/WhisperTests/Core/`, and existing Settings UI tests.

- [ ] Add failing tests: invalid `--release-version` values (`1.0`, `v1.0.1`, prerelease suffixes, shell metacharacters) reject before deleting an existing bundle; a valid `1.0.0` writes both version keys; the package remains signed after version injection; Settings displays the actual bundle version, not `1.0`.
- [ ] Replace the source plist's misleading release values with an explicit local-development version, e.g. `0.0.0` for both keys. Keep the normal no-argument `scripts/package.sh` path for verification and development. Add an optional `--release-version MAJOR.MINOR.PATCH` that accepts exactly three nonnegative decimal components and injects those values into the copied bundle **before** signing. Avoid editing the tracked plist during release.
- [ ] Extract the About-version presentation into a testable helper that reads `CFBundleShortVersionString` from the active bundle and labels development packages accordingly. Update the existing Settings UI expectations.
- [ ] Assert exact bundle ID, arm64 binary, matching version keys, signing authority, and certificate-bound designated requirement after packaging. Do not rely on a successful `codesign --deep` invocation alone for nested code.
- [ ] Run focused shell/Swift tests and `git diff --check`. Then run `./scripts/verify.sh` (UI on the built-in display). Record results in `WH-M7-001`.

## Task 2 — Sparkle client and signing-key setup (`WH-M7-002`)

**Files:** `project.yml`, `Resources/Info.plist`, `Sources/WhisperApp/AppDelegate.swift`, a new `Sources/Updates/UpdateController.swift`, `Sources/UI/MenuBar/MenuBarContentView.swift`, `Sources/UI/MenuBar/MenuBarController.swift`, `Sources/UI/Settings/SettingsView.swift`, `scripts/package.sh`, `Tests/WhisperTests/UI/MenuBarModelTests.swift`, new focused update-controller tests, and menu/Settings UI tests.

- [ ] Pin Sparkle `2.10.0` in XcodeGen's `packages` section with `exactVersion: 2.10.0`, then link/embed the `Sparkle` product in the Whisper target. The exact tracked version is authoritative because `Whisper.xcodeproj/` and its `Package.resolved` are ignored.
- [ ] Add failing tests for update availability: a published bundle version enables the updater and the menu action; a `0.0.0` development bundle does not start Sparkle or show an error; Check for Updates delegates exactly once; About shows installed version; dictation/meeting commands are unaffected.
- [ ] Add the fixed HTTPS `SUFeedURL`. Generate the Sparkle EdDSA key once with Sparkle's official `generate_keys` on the owner Mac, record only the public `SUPublicEDKey` in the tracked plist, and keep the private key in login Keychain. The implementation must pause for owner authorization if creation/access to this new signing secret is required.
- [ ] Own `SPUStandardUpdaterController` in the app lifecycle and expose a menu-bar **Check for Updates…** action. Let Sparkle handle periodic checks and the standard install prompt. Do not start checks in isolated UI-test mode or during non-release development launches.
- [ ] Inspect the copied bundle's `Contents/Frameworks/Sparkle.framework` and any embedded XPC/helpers. If the current `codesign --deep --sign` path breaks framework/helper validity, sign nested components in the documented inner-to-outer order with the same identity and verify each plus the outer app strictly. Keep the bundle's designated requirement stable across two clean packages.
- [ ] Run focused unit/UI tests, `xcodegen generate`, a clean signed package, `codesign --verify --deep --strict`, and `./scripts/verify.sh` on the built-in display. Record the pinned Sparkle version, generated public key fingerprint/identifier (not private material), and package evidence.

## Task 3 — Guarded local release and GitHub feed (`WH-M7-003`)

**Files:** new `scripts/release-local.sh`, a small shared release/version helper if necessary, `Tests/Scripts/ReleaseScriptTests.sh`, optional `Tests/Scripts/ReleaseFeedTests.sh`, `scripts/verify.sh` if script discovery needs adjustment, and `docs/operations/releasing.md`.

- [ ] Write shell contract tests with mocked `gh`, `git`, `codesign`, Sparkle tools, and a temporary fixture repository. First prove fail-closed behavior for wrong account/remote/branch, dirty tree, diverged HEAD, absent identity/key, invalid or already-published tag, zero or more than one unreleased post-bootstrap commit, unsigned appcast, mismatched versions/URLs, missing ZIP, and an existing asset. Assert no remote-write mock is called on any failed preflight.
- [ ] Implement a `--prepare` local-only mode first: derive `v1.0.0` for bootstrap or `v1.0.(PATCH+1)` from the latest published 1.0 tag; require one new `master` commit after bootstrap; run the full verification gate; invoke `scripts/package.sh --release-version`; archive only `Whisper.app` as `Whisper-VERSION.zip` with `ditto -c -k --sequesterRsrc --keepParent`; generate a signed appcast with Sparkle's `generate_appcast --download-url-prefix https://github.com/yurybv/whisper/releases/download/vVERSION/ --maximum-deltas 0` from a staging directory containing only that ZIP. Verify `sparkle:edSignature`, exact URL, length, version, and public key match. Do not publish merely because the generator exited zero.
- [ ] Implement a separate explicit `--publish` phase. Re-run the account/remote/branch/HEAD guard immediately before every GitHub mutation; verify the prepared artifact hash and version; create/push the exact tag and a draft GitHub Release targeting that SHA; upload ZIP and `appcast.xml`; inspect both draft assets and their sizes/digests; publish as a full/latest release only after completeness is proven. Never use `--clobber`, `--force`, or a floating branch ref for the release target.
- [ ] Verify public `https://github.com/yurybv/whisper/releases/latest/download/appcast.xml` and exact tagged ZIP URLs after publication. A partially prepared draft must not change `latest`; a resumed run may continue only after comparing SHA, version, and assets, otherwise stop with explicit manual recovery instructions. Do not automatically delete or replace a draft, tag, or published release.
- [ ] Run all release script tests, full `./scripts/verify.sh`, `git diff --check`, shell lint/syntax, and a dry-run of `--prepare`. Do **not** invoke `--publish` until the account is `yurybv`, Milestone 6 has passed, and the owner authorizes the first release.

## Task 4 — First release, real update, and operating guide (`WH-M7-004`)

**Files:** `README.md`, `docs/operations/releasing.md`, `docs/operations/troubleshooting.md`, `docs/testing/test-strategy.md`, `docs/testing/release-acceptance.md`, `docs/implementation/roadmap.md`, `docs/implementation/tasks/m7-updates.md`, `docs/implementation/task-backlog.md`, and an update-distribution ADR under `docs/architecture/adr/`.

- [ ] Document the one-time setup: Sparkle key generation and safe offline backup procedure; exact release command; why the local Mac must build/sign; first manual installation of the versioned ZIP at `/Applications/Whisper.app`; one-time Gatekeeper and permission migration; update troubleshooting; what to do if either signing key is lost. Do not publish private-key backup contents.
- [ ] After account/remote/branch verification, publish `v1.0.0` from the verified source commit. Download the public ZIP and feed, compare digests to prepared artifacts, inspect the extracted bundle's version, signature, Sparkle key, and `SUFeedURL`; install that exact ZIP once. Do not use GitHub's automatic source-code ZIP as an installer.
- [ ] Make one focused follow-up source commit and release it as `v1.0.1`. On the built-in display, run `/Applications/Whisper.app` at `1.0.0`, invoke **Check for Updates…**, accept the standard prompt, and confirm the same installed path relaunches at `1.0.1` without manual rebuild/copy. Also verify the periodic check path without requiring the user to operate the release script.
- [ ] Before and after update, compare the bundle identifier, signing certificate/designated requirement, and live macOS permissions. Confirm the saved OpenAI key, three built-in modes plus custom modes, history, recordings, global shortcuts, dictation, and meeting availability persist. Use synthetic text/audio where possible and do not save private content in evidence.
- [ ] Exercise failure cases with a local synthetic feed/archive (never poisoning the public latest feed): altered ZIP, wrong signature, bad URL, lower version, and unavailable network. Confirm the old installed app remains usable and recovery instructions are accurate.
- [ ] Update the ADR, README, roadmap, release acceptance matrix, task records, and backlog with actual results. Run `./scripts/verify.sh`, `git diff --check`, inspect the full diff and artifacts for secrets, then follow the repository completion/account guard before marking any task done or pushing future source commits.

## Task 5 — Milestone 7 review (`WH-M7-005`)

**Files:** `docs/implementation/reviews/m7-review.md`, `docs/implementation/tasks/m7-updates.md`, `docs/implementation/task-backlog.md`, `docs/implementation/roadmap.md`, `docs/testing/release-acceptance.md`, and any narrowly scoped documentation correction supported by review evidence.

- [ ] Audit all four task records against their acceptance evidence, the verified commits on `origin/master`, and the public `v1.0.0`/`v1.0.1` release assets. Confirm that no task was marked done on local-only or automated-only evidence.
- [ ] Review signing and EdDSA key continuity, GitHub account guard, appcast/ZIP integrity, permission and data persistence, failure recovery, privacy, and the built-in-display manual update matrix. Record remaining limitations rather than silently broadening scope.
- [ ] Run the complete repository verification gate and `git diff --check`. Update the roadmap, backlog, and review record together; mark Milestone 7 complete only if every criterion and source-of-truth record agrees.

## Planning checkpoint

The design, plan, and blocked future-task records can be committed locally so the next context window sees a clean worktree. No implementation, signing key, version tag, GitHub Release, push, or manual update QA has occurred. A non-`yurybv` GitHub CLI login must not be used for remote writes.
