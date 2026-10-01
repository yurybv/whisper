# Local Automatic Updates Implementation Plan

> **For agentic workers:** Follow the repository workflow and implement one task at a time with TDD. Use inline execution with `superpowers:executing-plans` when implementation is requested. The owner approved the update-first order and local release approach on 2026-10-01. This revision is planning work; it does not publish a release.

**Goal:** The owner requests a version in chat; the agent builds, verifies, signs, and publishes it, and the owner installs it through Whisper after one bootstrap installation.

**Architecture:** Sparkle 2 reads the stable GitHub latest-release appcast. A local command prepares an exact task/source checkpoint, validates it, and publishes a signed ZIP plus appcast under an immutable version tag. A prepared manifest makes retries resumable and relates a task's commit series to one patch version. The signing keys stay on this Mac.

**Tech Stack:** Swift 6/SwiftUI, Sparkle 2, XcodeGen, Bash, macOS `codesign`/`ditto`/Keychain, GitHub CLI and Releases.

**Design:** [Local Automatic Updates Design](../specs/2026-09-29-local-automatic-updates-design.md), revised 2026-10-01.

## Global constraints and sequencing

- Execute `WH-M7-001 → WH-M7-002 → WH-M7-003 → WH-M7-004 → WH-M7-005`, then deferred research `WH-M6-014`, any necessary scoped fixes, and `WH-M6-003 → WH-M6-005 → WH-M6-006`.
- M7 entry requires completed `WH-M6-002`, `WH-M6-004`, and `WH-M6-013`; the owner removed its former dependency on the M6 final review. M6 is still incomplete.
- Preserve `dev.yury.whisper`, the existing `Whisper Local Development` certificate and requirement, app storage, Keychain, and consent boundaries. Never replace the existing signing key to simplify setup.
- Use Apple Silicon, macOS 15+, Xcode 26.6+, Swift 6 mode, and the existing unsandboxed app. No paid developer account, notarization, cloud builder, or persistent runner is needed for this scope.
- Before remote mutations, enforce `gh` login `yurybv`, origin `https://github.com/yurybv/whisper.git`, and delivery branch `master`. Verify clean/synchronized source and the exact prepared SHA again before publication.
- Never put credentials, private keys, dictated text, transcripts, custom instructions, or Authorization headers in Git, output, artifacts, or QA evidence. Only generated acceptance content is permitted.
- Test behavior changes with failing-then-passing focused tests. Run the full `./scripts/verify.sh` for task completion; repeat only after source changes or a new concern. Reuse evidence for the same source/environment when preparing its release, while separately verifying the version-injected signed artifact.
- Keep UI/update acceptance on the built-in display. If a necessary OS action is unavailable to automation, give the owner one precise action and resume afterward; do independent checks first.
- Completion means verified source on `origin/master`. Release publication is a separate explicit owner command and does not follow automatically from a push.
- No implementation, build, key creation, tag, or public release is part of this plan-editing turn.

## Responsibility and owner effort

| Stage | Agent work | Owner participation |
|---|---|---|
| Task implementation | Code, tests, review, task records, guarded commit/push | Product choices only when materially ambiguous |
| One-time signing setup | Inspect/reuse identity; prepare and run official Sparkle key tooling after authorization | One setup authorization if missing; protected Keychain prompt if macOS requires it |
| Release | Resolve task, choose patch, verify exact source, build/sign, generate notes/assets, publish and verify | Say “выпусти обновление”; that command covers the release stages |
| First install | Prepare the released ZIP, preserve prior app, install at the fixed path, launch/inspect | Only unautomatable Gatekeeper/OS prompts or necessary installation action |
| Later update | Feed verification and post-update diagnostics | Check for Updates… and accept installation/relaunch |
| Remaining acceptance | Automated and agent-operable checks with synthetic content | Batched physical/audio checks that tools cannot substantiate |

Do not ask the owner to run a terminal command, pick a patch number, assemble assets, write release notes, or repeat a release authorization. Preparation must produce a concrete task/version/check summary before any missing publication approval is requested. If a release was already requested, continue through publication without another approval loop.

## File and interface map

The following are planned interfaces, not existing commands:

- `Sources/Core/AppVersion.swift`: validated bundle version and development label; used by Settings and the updater.
- `Sources/Updates/UpdateController.swift`: main-actor adapter around Sparkle; receives release/test configuration and busy state; exposes `checkForUpdates()` and observable availability.
- `scripts/package.sh --release-version 1.0.0`: inject both version keys before signing; the no-argument path stays a `0.0.0` development package.
- `scripts/release-local.sh --prepare --task WH-ID --source FULL_SHA`: read-only GitHub inspection plus local preparation; no remote writes. Prints the next version and an absolute manifest path.
- `scripts/release-local.sh --publish --manifest ABSOLUTE_PATH`: verify and publish the exact prepared artifacts, or resume/return the identical release. Never regenerate a different candidate implicitly.
- Bootstrap preparation additionally uses `--bootstrap initial` or `--bootstrap update`, only for `WH-M7-004` in `review`; permit respectively `1.0.0` and `1.0.1`.
- Prepared manifest: `schemaVersion`, `taskID`, `sourceSHA`, `baseTag`, `baseSHA`, `version`, `bootstrapPhase`, included commit SHAs with task/closure classification, verification source/evidence, signing/public-key fingerprints, artifact relative paths/sizes/SHA-256, and generated release notes. Resolve files only within the validated staging directory; shell-source/eval is prohibited.
- The published sanitized manifest (without local paths or private evidence), ZIP, and appcast tie task ID/version/source/digests together. Read prior release manifests to reject duplicate task releases. The agent supplies the task/source; the owner never edits a manifest.
- `docs/operations/releasing.md`: separate short owner instructions from the detailed agent/operator commands and recovery steps.

## Task 1 — Version metadata and package integrity (`WH-M7-001`)

**Files:** modify `Resources/Info.plist`, `Sources/UI/Settings/SettingsView.swift`, `scripts/package.sh`, `Tests/Scripts/PackageScriptTests.sh`, and the existing Settings UI test; create `Sources/Core/AppVersion.swift` and `Tests/WhisperTests/Core/AppVersionTests.swift`.

**Consumes:** current bundle metadata and persistent signing resolver. **Produces:** validated `MAJOR.MINOR.PATCH` bundle versions, visible installed version, and the package interface above.

- [ ] Add package tests that preserve a sentinel prior bundle while rejecting `1.0`, `v1.0.1`, `01.0.1`, suffixes, negative/overflow components, and shell metacharacters. Add tests for `0.0.0` development display, `1.0.0` installed display, and equal short/build versions.
- [ ] Run `bash Tests/Scripts/PackageScriptTests.sh` and the new `WhisperTests/AppVersionTests` selection. Confirm expected assertion failures before implementation.
- [ ] Implement strict three-component decimal validation and version injection into the copied bundle before signing. Keep the tracked plist at `0.0.0`; a release must never modify source metadata. Read About from the current bundle.
- [ ] Rerun focused tests, build `./scripts/package.sh --release-version 1.0.0`, inspect both plist keys, certificate/requirement, architecture, and `codesign --verify --deep --strict build/Whisper.app`.
- [ ] Run the full verification gate and `git diff --check`; record evidence, review the diff, commit/push under repository guards, and unlock only `WH-M7-002`. No installed-app replacement or publication occurs.

## Task 2 — Sparkle client, busy-state handling, and signing setup (`WH-M7-002`)

**Files:** modify `project.yml`, `Resources/Info.plist`, `Sources/WhisperApp/AppDelegate.swift`, `Sources/WhisperApp/AppRuntime.swift`, menu-bar and Settings UI, `scripts/package.sh`; create `Sources/Updates/UpdateController.swift`, `Tests/WhisperTests/Updates/UpdateControllerTests.swift`, `scripts/setup-update-signing.sh`, and `Tests/Scripts/UpdateSigningTests.sh`; extend relevant UI/package tests.

**Consumes:** `AppVersion`, existing capture/processing states, existing code-signing identity. **Produces:** updater lifecycle/manual action, safe installation deferral, public EdDSA key metadata, and verified nested-code packaging.

- [ ] Verify the previously selected Sparkle `2.10.0` exists and its official release/tool documentation supports this Mac. Keep an exact XcodeGen package pin; record a supported 2.x replacement only if evidence requires one. Resolve the tool binaries from that same pinned distribution, not an unrelated global installation.
- [ ] Add failing tests: release configuration starts once; `0.0.0` and isolated UI tests do not start/check a live feed; menu and Settings actions call the same adapter once; busy capture/processing defers install/relaunch; idle resumes; unavailable feed leaves the app usable. Use an injected fake update driver for deterministic tests.
- [ ] Add idempotent setup tests: an existing matching public key is reused; conflicting/missing configured state is reported without rotation; no private key is printed or exported. Prepare all code/tests before the one signing-secret checkpoint.
- [ ] Implement the adapter, both **Check for Updates…** entry points, and the fixed HTTPS feed URL. Use Sparkle's documented delegate mechanisms for installation deferral; do not assume the standard UI alone protects a recording. Pass actual coordinator state into the gate rather than relying on a visible HUD.
- [ ] If not previously authorized, request one-time creation of the local Sparkle key only when needed. Then run the official `generate_keys` through the setup helper, keep the private key in login Keychain, and store only the matching public `SUPublicEDKey` in the plist. Let the owner handle any protected authentication dialog.
- [ ] Audit framework/XPC/helper signing using the pinned Sparkle guidance. Preserve required helper entitlements and symlinks; sign in the required inner-to-outer order. Verify each embedded executable and the outer bundle, then compare certificate and designated requirement across two packages.
- [ ] Run `bash Tests/Scripts/UpdateSigningTests.sh`, focused Swift/UI tests, `./scripts/verify.sh`, and `git diff --check`. Commit/push verified work and unlock `WH-M7-003`.

## Task 3 — Agent-operated task releases and resumable publication (`WH-M7-003`)

**Files:** create `scripts/release-local.sh`, `scripts/release-manifest.swift` (Foundation-based JSON/XML parsing and validation), `Tests/Scripts/ReleaseScriptTests.sh`, `Tests/Scripts/ReleaseFeedTests.sh`, and `docs/operations/releasing.md`; extend `scripts/verify.sh` only if discovery requires it.

**Consumes:** versioned package interface, pinned Sparkle signing tools, completed task records, immutable `origin/master` checkpoints. **Produces:** prepare/publish CLI and manifest described above; tagged assets with task/source provenance.

- [ ] Build shell fixtures using temporary Git repositories and mocked external tools. Assert failure before remote writes for wrong account/remote/branch, dirty/diverged source, unverified SHA, source outside `origin/master`, incomplete/duplicate task, unexplained changed files, malformed manifest/path escape, changed keys, and mismatched archive/feed values.
- [ ] Add positive tests for one completed task spanning multiple commits, related metadata-only closure commits, and two queued tasks published separately in order. Reject a combined unexplained range. Add normal-release rejection of zero new source changes and duplicate version/task IDs.
- [ ] Add bootstrap tests: only the two named phases for `WH-M7-004` in `review` with tasks 001–003 done are allowed; all other incomplete-task releases remain rejected.
- [ ] Run `bash Tests/Scripts/ReleaseScriptTests.sh` and `bash Tests/Scripts/ReleaseFeedTests.sh`; confirm expected failures.
- [ ] Implement `--prepare`: fetch/inspect release state read-only, derive the next version, resolve the requested checkpoint and classified commit range, reuse exact-source verification evidence or run the gate, package that source with the version, and stage only approved artifacts outside the source tree. An older task checkpoint builds in an isolated checkout; never reset or overwrite the user's working tree.
- [ ] Archive with `ditto -c -k --sequesterRsrc --keepParent`. Use the pinned `generate_appcast` with the exact tagged download prefix and deltas disabled. Parse XML; verify the enclosure signature against the configured public key, URL, byte length, both versions, architecture, bundle ID, nested signatures, and artifact digests. A successful generator exit alone is insufficient.
- [ ] Generate a sanitized release description from the task's actual changes/checks and include outstanding personal-testing limitations with `WH-M6-014` while it is unresolved. Write the local manifest and sanitized public manifest; do not upload local test logs, raw xcresults, or user data.
- [ ] Implement explicit `--publish`: rerun guards; compare manifest/source/digests; create the exact tag and draft targeting the full SHA; upload ZIP, appcast, and sanitized manifest; download the draft assets with authenticated reads and compare digests; only then publish as latest. Use structured API fields or a body file for multiline notes.
- [ ] Reconcile timeouts by reading remote tag/release/assets. Identical drafts resume, identical completed requests return the same release, conflicting assets stop. Test failures after tag creation, draft creation, individual upload, and publication. Never overwrite/delete assets or increment a version simply because a retry occurred.
- [ ] Verify the public latest feed, exact tagged ZIP, and manifest after publication. Report a failed public check explicitly; retain the verified local artifacts for diagnosis. Pre-publication failures leave the previous latest untouched.
- [ ] Run the script suites, shell validation, `./scripts/verify.sh`, and `git diff --check`. Exercise local-only preparation with synthetic repositories. After the task is done on `origin/master`, real bootstrap preparation can run in Task 4. No publication is necessary to finish Task 3.

## Task 4 — Bootstrap, real update, and minimal owner runbook (`WH-M7-004`)

**Files:** `README.md`, `docs/operations/releasing.md`, `docs/operations/troubleshooting.md`, `docs/testing/test-strategy.md`, new `docs/testing/update-acceptance.md`, sanitized `docs/testing/evidence/WH-M7-004/qa.md`, an update-distribution ADR, task/backlog/roadmap records.

**Consumes:** verified updater and release command. **Produces:** actual public `1.0.0 → 1.0.1` evidence and installed path/version continuity.

- [ ] Prepare the acceptance checklist/runbook and commit its source checkpoint under Task 4; move to `review` when implementation/check preparation is ready. Do not mark done before the real update. The bootstrap exception resolves the dependency between publication and this task's own acceptance.
- [ ] Prepare `1.0.0` locally and report exact source, asset checks, and known limitations. If the owner has not requested the bootstrap pair yet, the sole publication request is for both testing releases and their one-time install/update verification. Existing authorization for that pair must not be requested again.
- [ ] Publish/verify `1.0.0`. Inspect/download its public ZIP and manifest, compare hashes, inspect the extracted app, preserve the prior installed bundle recoverably, and install exactly at `/Applications/Whisper.app`. Coordinate safe closure of any active capture first; never force-quit or discard it to make installation proceed.
- [ ] Perform launch, version, menu/Settings action, and feed checks. The agent handles supported UI/file steps. Give the owner only the immediate OS authentication/consent or unavailable UI step if needed. Never weaken Gatekeeper or TCC.
- [ ] Commit the focused bootstrap acceptance preparation/results or a verified update-specific correction for the second checkpoint. Prepare/publish `1.0.1` under the same bootstrap authorization and exception. Do not make unrelated feature changes for a version bump.
- [ ] From the installed `1.0.0`, exercise **Check for Updates…**, standard installation/relaunch, and verify `1.0.1` at the same path. Also verify periodic checking and the busy-to-idle installation gate with generated fixtures. Do not copy a newer bundle manually to claim update success.
- [ ] Compare certificate/requirement, permissions, Keychain availability, modes, history, and recordings before/after without logging content or secrets. Baseline Right Option/menu-stop uncertainty stays in `WH-M6-014`; an update-specific regression blocks this task. If continuity cannot be observed, record it as pending, not passed.
- [ ] Exercise tampered ZIP, wrong signature, malformed feed, bad URL, downgrade, and offline cases against an isolated fixture feed/installed test copy, never the public latest feed. Confirm failed updates preserve the prior app/data.
- [ ] Finish the owner guide: request a release in chat, open the update UI, accept installation, read installed version. Keep build commands and technical recovery in an agent/operator section. Explain one-time prompts and that local publication requires this Mac.
- [ ] Record actual results; run required verification for any changed source, `git diff --check`, and privacy review of evidence. Commit/push closure and mark done only after acceptance. Map final evidence commits to future releases as metadata-only closure rather than inventing another app version.

## Task 5 — Update channel review (`WH-M7-005`)

**Files:** `docs/implementation/reviews/m7-review.md`, M7 task/backlog/roadmap records, `docs/testing/update-acceptance.md`, and narrowly scoped documentation corrections.

- [ ] Audit tasks 001–004 against source commits, manifests, actual public release assets, and installed update evidence.
- [ ] Verify multi-commit task mapping, duplicate/retry behavior, generated release notes, key continuity, failure handling, idle installation, data/permission checks, and the short owner workflow.
- [ ] Run `./scripts/verify.sh` and `git diff --check`; review privacy and relevant diff. Record unresolved limitations. Do not promote M6 acceptance or the dictation report to passed based on this review.
- [ ] Commit/push the review, mark M7 done only after its checks pass, and unlock `WH-M6-014`. Keep `WH-M6-003` blocked until research and any resulting blocking fixes are addressed.

## Final queued research — Right Option and stop control (`WH-M6-014`)

The full record is in [m6-release.md](../../implementation/tasks/m6-release.md#wh-m6-014). This is deliberately last in the development/research queue; final acceptance and the MVP readiness review follow it.

- [ ] Use the installed, versioned app delivered through the update UI. Record version/source, selected shortcut, permission state, and exact start/stop sequence using synthetic audio.
- [ ] Reproduce the reported Option hold and menu **Start Dictation** behavior, distinguish missing input events, wrong UI state, recorder lifecycle, and processing delays. The report is unresolved; no root cause is assumed.
- [ ] Inspect recorder/coordinator/hotkey/menu/HUD boundaries without logging private content. Confirm whether stop/cancel stops capture and whether fallback controls remain reachable when hotkeys are unavailable.
- [ ] Produce a sanitized research note with reproduced behavior, evidence-backed cause or explicit unknown, smallest proposed correction, and a regression-test plan. Create scoped local bug tasks for confirmed issues; do not silently turn research into a UI redesign.
- [ ] After research and any blocking fixes, resume the preserved M6 acceptance matrix on the versioned installed app. Finish the operating guide and M6 final review afterward.

## Planning checkpoint

This 2026-10-01 revision changes only documentation and task scheduling. `WH-M7-001` is ready; `WH-M6-003` is deferred/blocked with its evidence intact; `WH-M6-014` is the final queued research item. No task is newly done, no update is implemented, and no key, build, tag, release, or installation has been produced by this planning revision. Leave the changes available for review; continue with the first implementation task when requested.
