# Milestone 7: Local automatic updates

Planning status: revised 2026-10-01 under the owner's explicit update-first decision; version metadata (`WH-M7-001`), signed updater integration (`WH-M7-002`), and guarded local release automation (`WH-M7-003`) are complete. Live bootstrap verification (`WH-M7-004`) is ready. The former `WH-M6-006` entry gate is replaced by completed verification, privacy, and stable-signing prerequisites. M6 acceptance stays open. All tasks link to the revised [design](../../superpowers/specs/2026-09-29-local-automatic-updates-design.md) and [implementation plan](../../superpowers/plans/2026-09-29-local-automatic-updates.md).

Owner workflow: request a release in chat, then use **Check for Updates…** in Whisper. The agent runs all build, signing, versioning, packaging, and publishing commands. One completed task may contain several commits and maps to one patch release when requested. One initial installation is accepted; protected OS confirmations remain with the owner. The owner authorized the one-time local updater key creation on 2026-10-02; source delivery still does not authorize release publication.

## WH-M7-001

- **Title:** Embed release versions in signed bundles
- **Type:** build
- **Status:** done
- **Priority:** P0
- **Scope:** Add validated version injection before final signing; display installed bundle version in Settings; distinguish development packages.
- **Out of scope:** Publishing tags/releases, Sparkle integration, installation, or changing bundle identity/storage.
- **Acceptance criteria:** Release short/build versions match the validated argument; invalid versions leave the previous package intact; About reads installed metadata; development builds are labeled; signatures remain valid. Task/source release mapping belongs to WH-M7-003.
- **Required checks:** TDD package/version/UI tests from plan Task 1; versioned package/plist/signature inspection; `./scripts/verify.sh`; `git diff --check`.
- **Dependencies:** WH-M6-002, WH-M6-004, WH-M6-013.
- **Expected files:** `Resources/Info.plist`, `scripts/package.sh`, `Sources/Core/AppVersion.swift`, Settings/version tests and UI.
- **Source:** implementation plan Task 1; owner-approved reprioritization on 2026-10-01.
- **Evidence:** Red-green shell and Swift tests; focused Settings UI test; a signed `1.0.0` package verified matching bundle values, arm64 architecture, and its stable designated requirement. `./scripts/verify.sh --skip-ui-tests` passed because unrelated foreground windows blocked the full UI suite; the changed Settings UI test ran successfully.
- **Blockers:** None.

## WH-M7-002

- **Title:** Integrate a signed Sparkle updater
- **Type:** feature
- **Status:** done
- **Priority:** P0
- **Scope:** Pin/embed Sparkle, configure the feed/public key, expose Check for Updates in menu and Settings, defer installation/relaunch while capture or processing is active, and verify embedded-code signing.
- **Out of scope:** Cloud builds, custom updater UI, silent replacement during active work, public publication, and the deferred dictation investigation.
- **Acceptance criteria:** Release builds start the updater once; development and isolated UI-test launches do not; both manual actions share the adapter; busy-to-idle deferral protects active work; setup reuses the same EdDSA key; framework/helpers and app verify with the stable identity; private key stays in Keychain.
- **Required checks:** TDD updater/installation-state/menu/UI and key-setup tests from plan Task 2; two signed package comparisons; `./scripts/verify.sh`; `git diff --check`.
- **Dependencies:** WH-M7-001.
- **Expected files:** `project.yml`, `Resources/Info.plist`, `Sources/Updates/UpdateController.swift`, app lifecycle/state wiring, menu/Settings UI, package signing, `scripts/setup-update-signing.sh`, focused tests.
- **Source:** implementation plan Task 2.
- **Evidence:** Sparkle 2.10.0 is pinned exactly; release-only lifecycle, shared manual actions, unavailable-feed retry, and busy-to-idle installation handling passed focused Swift/UI tests. Matching-key reuse, conflict refusal, and explicit setup passed shell fixtures without secret output. Two fresh signed `1.0.0` packages produced identical authorities and certificate-bound designated requirements for the app, framework, Updater, Autoupdate, and both XPC services. The canonical gate passed with 330 unit tests, 17 UI tests, shell/privacy checks, packaging, and strict signature verification; `git diff --check` passed.
- **Blockers:** None.

## WH-M7-003

- **Title:** Prepare and publish guarded local releases
- **Type:** build
- **Status:** done
- **Priority:** P0
- **Scope:** Agent-operated prepare/publish phases, task-to-version mapping across related commits, immutable source/artifact manifests, generated notes, signed ZIP/appcast, draft verification, and resumable latest publication.
- **Out of scope:** Hosted/self-hosted runners, GitHub Pages, replacing published assets, automatic publication on push, and a new task-tracking service.
- **Acceptance criteria:** One completed task maps to one patch even with multiple commits; unexplained changes and duplicate tasks are rejected; multiple queued tasks can be released separately in order. Guards prevent remote writes on invalid state. Retries resume the same version/assets; identical published requests are idempotent. ZIP/appcast/public manifest agree with exact source and keys; only a verified draft becomes latest. Public URL verification is explicit. Bootstrap exception is limited to WH-M7-004's two verified review checkpoints.
- **Required checks:** Failing-then-passing release/manifest/feed shell tests including mutation-boundary failures; local-only preparation against synthetic repositories; `./scripts/verify.sh`; `git diff --check`.
- **Dependencies:** WH-M7-002.
- **Expected files:** `scripts/release-local.sh`, `scripts/release-manifest.swift`, `Tests/Scripts/ReleaseScriptTests.sh`, `Tests/Scripts/ReleaseFeedTests.sh`, `docs/operations/releasing.md`.
- **Source:** implementation plan Task 3 and its file/interface map.
- **Evidence:** Typed local/public manifests, Ed25519 manifest seals, exact Sparkle feed validation, detached-source preparation, fail-closed repository guards, draft/asset verification, mutation-boundary resume tests, and idempotent publication tests pass. A real signed release package also passed architecture and nested-signature validation. Public publication is intentionally deferred to the owner-authorized bootstrap task.
- **Blockers:** None. Public publication is not required to complete this implementation task. A later owner release command authorizes the whole publication workflow; the agent handles commands and version selection without repeated approvals.

## WH-M7-004

- **Title:** Verify first install and automatic patch update
- **Type:** testing
- **Status:** ready
- **Priority:** P0
- **Scope:** Agent-prepared bootstrap releases and one installation at /Applications, actual 1.0.0 → 1.0.1 Sparkle update, busy-state and failure checks, permission/data continuity, and a short owner guide.
- **Out of scope:** Notarization, other-Mac distribution, fixing the deferred Right Option/menu-stop report, and requiring recurring owner build/copy commands.
- **Acceptance criteria:** Verified public assets install once; the installed app then updates through its own UI to 1.0.1 at the same path. Signing and observed permissions/Keychain/modes/history/recordings survive; failed/tampered updates preserve the prior app; active work defers installation. Owner instructions require only requesting a release, in-app update actions, and genuinely necessary OS consent. Known baseline dictation uncertainty remains recorded separately.
- **Required checks:** Public archive/feed/manifest digests and signatures; actual built-in-display update/continuity matrix in `docs/testing/update-acceptance.md`; failure fixtures; `./scripts/verify.sh`; `git diff --check`; evidence privacy review.
- **Dependencies:** WH-M7-003.
- **Expected files:** README, release/operations guide, update acceptance/evidence, ADR, roadmap and task records.
- **Source:** implementation plan Task 4.
- **Blockers:** Missing explicit bootstrap publication command or an unavoidable OS confirmation at execution time. Complete preparation before asking. The two bootstrap releases may use verified checkpoints while this task is in review; do not mark it done before live update evidence exists.

## WH-M7-005

- **Title:** Review automatic update release readiness
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Audit update implementation, task/version mapping, release integrity/retries, real update continuity, owner effort, privacy, and status consistency.
- **Out of scope:** New updater features or treating update-channel readiness as completed MVP/dictation acceptance.
- **Acceptance criteria:** WH-M7-001..004 are done on origin/master; manifests and real 1.0.0 → 1.0.1 evidence agree; all update-specific failures are resolved; owner workflow requires no recurring builds or file copies. The unresolved dictation report remains visible and WH-M6-014 becomes ready; WH-M6-003 remains blocked pending research and any necessary fix.
- **Required checks:** `./scripts/verify.sh`; `git diff --check`; inspect public release assets/manifests, update evidence, dependencies, and owner instructions.
- **Dependencies:** WH-M7-001..004.
- **Expected files:** `docs/implementation/reviews/m7-review.md`, task/backlog/roadmap records, update acceptance documentation.
- **Source:** implementation plan Task 5 and the owner-approved milestone-order exception.
- **Blockers:** WH-M7-001..004. Update-specific continuity failures or missing manual update evidence prevent completion; the pre-existing dictation issue remains assigned to the final research task.
