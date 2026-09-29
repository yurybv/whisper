# Milestone 7: Local automatic updates

Planning status: recorded locally on 2026-09-29; no implementation started. Milestone 7 is gated by `WH-M6-006` and remains blocked until the Milestone 6 review is done. All tasks link to the [design](../../superpowers/specs/2026-09-29-local-automatic-updates-design.md) and [implementation plan](../../superpowers/plans/2026-09-29-local-automatic-updates.md).

## WH-M7-001

- **Title:** Embed release versions in signed bundles
- **Type:** build
- **Status:** blocked
- **Priority:** P1
- **Scope:** Add validated version injection before final signing; display the installed bundle version in Settings; distinguish non-release development packages.
- **Out of scope:** Publishing tags/releases, Sparkle integration, or changing bundle identity/storage.
- **Acceptance criteria:** The release package's short/build versions match the validated version supplied by the release command; invalid versions stop before changing the existing package; About reads installed metadata; signatures remain valid. Git-tag derivation belongs to `WH-M7-003`.
- **Required checks:** Failing-then-passing package shell and version/UI tests; `./scripts/verify.sh`; `git diff --check`; inspect packaged plist and signature.
- **Dependencies:** WH-M6-006.
- **Expected files:** `Resources/Info.plist`, `scripts/package.sh`, Settings/version source and tests.
- **Source:** implementation plan Task 1.
- **Blockers:** Milestone 6 review not done. This planning-only turn must not change its status.

## WH-M7-002

- **Title:** Integrate a signed Sparkle updater
- **Type:** feature
- **Status:** blocked
- **Priority:** P1
- **Scope:** Pin/embed Sparkle, add feed/public-key metadata, start updater for release builds, expose Check for Updates, and verify embedded-code signing.
- **Out of scope:** Cloud build automation, custom updater UI, silent updates, and public release publication.
- **Acceptance criteria:** Release app can check the feed; development app does not start a misconfigured updater; manual check action works; nested framework/helpers and outer app verify with stable identity; private EdDSA key stays local.
- **Required checks:** Failing-then-passing updater/menu tests and UI test; signed package framework checks; `./scripts/verify.sh`; `git diff --check`.
- **Dependencies:** WH-M7-001.
- **Expected files:** `project.yml`, `Resources/Info.plist`, updater lifecycle/UI files, package signing, focused tests.
- **Source:** implementation plan Task 2.
- **Blockers:** WH-M7-001; owner authorization for one-time creation of a Sparkle signing secret when implementation reaches that step.

## WH-M7-003

- **Title:** Prepare and publish guarded local releases
- **Type:** build
- **Status:** blocked
- **Priority:** P1
- **Scope:** Local version/tag derivation, fail-closed account and repository guard, versioned ZIP and EdDSA appcast generation, draft release upload, and latest publication.
- **Out of scope:** A GitHub-hosted runner, GitHub Pages, replacing published assets, or automatic remote publication without this Mac.
- **Acceptance criteria:** Wrong account/repository/state causes no remote writes; `v1.0.0` bootstraps, then exactly one new commit maps to the next patch; ZIP/appcast metadata and signatures agree; only a complete draft becomes latest; prior feed remains usable on failure.
- **Required checks:** Failing-then-passing mocked release script tests, invalid-input/security cases, local prepare dry-run, full `./scripts/verify.sh`, `git diff --check`.
- **Dependencies:** WH-M7-002.
- **Expected files:** `scripts/release-local.sh`, `Tests/Scripts/ReleaseScriptTests.sh`, release runbook.
- **Source:** implementation plan Task 3.
- **Blockers:** WH-M7-002; publication additionally requires `gh` login `yurybv`, correct HTTPS remote/master, verified source commit, and explicit owner authorization.

## WH-M7-004

- **Title:** Verify first install and automatic patch update
- **Type:** testing
- **Status:** blocked
- **Priority:** P1
- **Scope:** Publish and install the first release, exercise `1.0.0 → 1.0.1` through Sparkle on the built-in display, verify permission/data continuity, and finish operating documentation/review.
- **Out of scope:** Notarization, other-Mac installation, beta channels, and paid distribution.
- **Acceptance criteria:** Public Release assets download correctly; installed app updates at the same path without manual rebuild; version changes; TCC grants, Keychain key, modes, history, and recordings remain; tampered/unavailable update leaves old app working; documentation matches observed behavior.
- **Required checks:** Public asset and signature/digest checks; full `./scripts/verify.sh`; manual built-in-display update/permission/data matrix; `git diff --check`; source/privacy review.
- **Dependencies:** WH-M7-003.
- **Expected files:** release/test/operations docs, roadmap, ADR, task and backlog evidence.
- **Source:** implementation plan Task 4.
- **Blockers:** WH-M7-003; real publication and manual QA require `yurybv` account and owner participation for macOS consent. Do not mark done from automated evidence alone.

## WH-M7-005

- **Title:** Review automatic update release readiness
- **Type:** review
- **Status:** blocked
- **Priority:** P1
- **Scope:** Audit the completed Milestone 7 implementation, release and manual-update evidence, privacy, signing continuity, task statuses, and operational documentation.
- **Out of scope:** New updater features, extra distribution channels, or silently waiving failed acceptance criteria.
- **Acceptance criteria:** Tasks `WH-M7-001` through `WH-M7-004` are done with verified commits on `origin/master`; the public `1.0.0 → 1.0.1` update and permission/data continuity have documented live evidence; release safety and recovery are reviewed; backlog and roadmap agree with the evidence.
- **Required checks:** `./scripts/verify.sh`; `git diff --check`; inspect public release assets and task evidence; review the built-in-display acceptance matrix.
- **Dependencies:** WH-M7-001..004.
- **Expected files:** `docs/implementation/reviews/m7-review.md`, task/backlog/roadmap records, release acceptance documentation.
- **Source:** implementation plan Task 5 and the repository milestone-review rule.
- **Blockers:** WH-M7-001..004 must be done; a failed real update or missing manual permission-continuity check blocks completion.
