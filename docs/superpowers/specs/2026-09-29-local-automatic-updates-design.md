# Local Automatic Updates Design

Date: 2026-09-29; revised 2026-10-01 after the owner's update-first decision

Status: owner-selected local release workflow; revised plan ready; implementation pending

Audience: owner and implementation agent

## Goal

Install Whisper once, then let the installed macOS app discover and install later signed releases without the owner running build commands or copying app bundles. The agent builds and signs on this Mac. Start at `1.0.0`; use `v1.0.0`, `v1.0.1`, and subsequent Git tags as the release-version source of truth. One completed task receives one next patch version when the owner requests its release; a task may contain several related commits.

The 2026-10-01 owner decision explicitly supersedes the previous post-MVP sequencing: implement `WH-M7-001..005` first, then investigate Right Option/menu-started dictation in `WH-M6-014`, then resume the remaining M6 acceptance, operating guide, and review. M6 remains incomplete. Early updates are personal testing releases with known dictation limitations; successful updater QA must not be described as MVP readiness.

## Owner interaction contract

- After a task is completed, the owner can say “release this task” or “выпусти обновление”. The agent resolves the task, prepares release notes, runs checks, assigns the next patch, signs, publishes, and verifies the public assets. No separate approval is requested for each technical stage of the same authorized release.
- Task completion and source pushes alone do not authorize a release. Preparation can proceed locally; publication waits for the owner's release command. Report the exact prepared task/version and a concrete blocker only if one exists.
- Normal owner steps are opening Whisper, choosing **Check for Updates…**, and accepting Sparkle's install/relaunch prompt. Periodic checks can offer the same update. Building still occurs on the signing Mac, but the owner never needs to run the build script.
- The owner approved one bootstrap installation at `/Applications/Whisper.app`. The agent prepares the verified public ZIP, preserves the previous installed bundle recoverably, installs and launches the new bundle when authorized and supported, and verifies the installed version. The owner performs only protected OS confirmations or an unavailable UI action.
- New signing-secret setup is a single explicit setup checkpoint if it has not already been authorized. Once approved, the agent uses the official tools, reuses the same key, and never asks for key contents. macOS Touch ID/password/permission dialogs remain with the owner; the agent supplies the exact immediate action and resumes from that step.
- Complete all automated and agent-operable checks first. Batch remaining physical, hearing, or OS-consent checks into a short checklist for the actual installed version. Do not repeatedly ask the owner to open windows or rerun commands that tools can perform.
- This planning revision authorizes changes to plans and task ordering, not immediate key creation, installation, Git tags, or public release publication.

## Current constraints

- Whisper is an unsandboxed, Apple Silicon macOS 15+ menu-bar app with bundle identifier `dev.yury.whisper`.
- `scripts/package.sh` builds an unsigned Release bundle and signs its final copy with the persistent, self-signed `Whisper Local Development` identity in this Mac's login Keychain. The signing private key was imported as non-extractable and must stay on this Mac.
- `Resources/Info.plist` currently contains static `1.0`/`1` values, and Settings displays a hard-coded version. Neither can identify releases correctly.
- The repository uses XcodeGen and `scripts/verify.sh`; generated Xcode projects are not source of truth.
- GitHub repository `yurybv/whisper` is public. Always verify the active account before writes; it must be `yurybv`. No code, tag, release, or remote operation is authorized merely by reading this planning document.

## Selected design

### Update client

Use a pinned stable Sparkle 2 release through XcodeGen's Swift Package dependency. Start `SPUStandardUpdaterController` programmatically in the normal app lifecycle, retain it for the process lifetime, and expose **Check for Updates…** in both the menu bar and Settings/About. Sparkle performs periodic background checks and presents its standard update/installation UI. Keep its user preference/consent flow. Installation/relaunch is deferred while dictation, meeting capture/finalization, or active processing could lose work; an idle-state transition permits retry without force-terminating a session. Settings/About reads the version from the installed bundle rather than a literal string. Test the busy-to-idle gate with synthetic state, independently of the deferred hotkey issue.

The released bundle contains:

- `SUFeedURL = https://github.com/yurybv/whisper/releases/latest/download/appcast.xml`;
- the public Sparkle EdDSA key in `SUPublicEDKey`;
- matching `CFBundleShortVersionString` and `CFBundleVersion`, starting at `1.0.0`.

Development builds with the non-release `0.0.0` version must not start the updater or display a misleading update error. The public key is not secret; Sparkle's private EdDSA key remains in the local login Keychain and never enters Git, a GitHub secret, a log, or a release. Use Sparkle's `generate_keys` once and `generate_appcast` for each release. Pin Sparkle to an exact version in the tracked XcodeGen specification.

### Version and release identity

Git tags identify published releases, not a version literal committed to Swift code. The local release command derives the candidate from the latest published `v1.0.PATCH` tag (first release `v1.0.0`, next `v1.0.1`) and injects it into both Info.plist version keys **before** final code signing. It verifies that the bundled version, appcast version, tag, asset name, and release title agree. A normal development package retains a clearly non-release version and is never published.

For normal releases, record the completed task ID, exact source SHA, base release, included commit range, next version, artifact digests, and verification evidence in a prepared release manifest. Select the source checkpoint for that task from verified `origin/master` history; the tag must resolve to that exact SHA. A task's test/fix/documentation commits share one release. Explicitly identify metadata-only task/review closure commits included since the prior release. Reject unexplained application changes, already released task IDs, an unchanged source, non-ancestor bases, downgrades, or incomplete tasks. If more than one unreleased task is present, prepare separate task releases in order; do not silently combine them or force the owner to count commits.

`--prepare` computes and retains a candidate; only publication consumes it. Repeating a failed command uses the same manifest/version/digests. Published assets are immutable, and an identical already-published request returns that release instead of incrementing again. The release command does not create a source-code commit. A small local staging manifest is sufficient; do not introduce a new issue tracker or hosted release service.

Bootstrap exception: `WH-M7-004` verifies both `1.0.0` and `1.0.1` before it can be marked done. Permit only those two verified checkpoints while it is in `review`, with `WH-M7-001..003` done and an owner command explicitly covering the bootstrap pair. The first includes the updater infrastructure; the second includes that task's documented acceptance preparation or a verified correction. Do not invent unrelated product changes merely to increase a version. Final post-update evidence can be committed afterward and mapped as metadata-only closure in the next release. This exception does not allow later incomplete feature tasks to be published.

### Hosting and publication

The agent runs the local release command on this Mac after the task's verified source reaches `origin/master` and the owner requests publication. It builds the exact checkpoint, packages with the existing local certificate, creates `Whisper-1.0.PATCH.zip` with `ditto` (preserving framework symlinks), generates an `appcast.xml` whose ZIP enclosure carries Sparkle's EdDSA signature, and uploads both to a **draft** GitHub Release for the exact tag. The feed itself is not additionally signed in this first version. Check draft assets through authenticated reads and compare downloaded digests before publishing as `latest`; public URLs are checked only after publication because drafts are not public. The stable feed URL resolves to the new appcast; each enclosure points to its own exact tagged ZIP URL. No GitHub Pages site, separate installer server, GitHub-hosted signing key, or paid Apple Developer membership is needed.

The script is fail-closed and idempotent: it refuses the wrong `gh` account, remote, delivery branch, dirty tree, diverged `origin/master`, missing/changed signing identities, missing Sparkle key, conflicting release/tag/assets, missing or invalid enclosure signature, malformed feed, or URL/version mismatch. The delivery checkout remains clean and synchronized; an older task checkpoint may build in an isolated staging checkout after proving it belongs to `origin/master`. It never overwrites an existing published release. If publication fails before the draft is published, the previous latest release and feed remain live. A timeout after publication is reconciled by reading remote state before retrying. A post-publication URL failure is reported as a failed verification, never as success; inspect/retry it without deleting or replacing the release. Local staging is outside the tracked source tree and must not contain user recordings or credentials.

There is no automatic cloud build on every push. The existing non-extractable signing key stays on this Mac, so agent-operated publication requires this Mac to be available. A permanently running self-hosted runner is outside this implementation.

### Signing, installation, and migration

Preserve the same app bundle identifier, app path, local certificate, and designated requirement across updates. Add explicit verification for Sparkle's embedded framework and helpers; the present `codesign --deep --sign` packaging must be audited and adjusted as needed rather than assumed sufficient. An update archive must be EdDSA signed and served over HTTPS. GitHub's public Release ZIP is an app archive, not a GitHub source ZIP.

The first `1.0.0` release needs one installation outside the updater because older builds do not contain one. Install that released ZIP's `Whisper.app` at the fixed `/Applications/Whisper.app` path, complete any one-time Gatekeeper/permission migration, and then verify `1.0.0 → 1.0.1` with the same signing identity. The agent handles preparation/copy/inspection when tools permit; a necessary owner click is described at the moment it is needed. Subsequent QA uses the installed app at this path, not a competing development copy. A self-signed certificate is for the owner's Mac, not notarized public distribution. Permission and Keychain continuity are acceptance criteria to verify, not guarantees inferred from a signature alone. Losing or replacing either signing key requires explicit recovery; never rotate either silently or export the non-extractable code-signing key.

## Acceptance

1. A fresh `1.0.0` release shows version `1.0.0` and can check the public feed.
2. With `v1.0.1` published, the installed `1.0.0` app offers and installs `1.0.1` without a manual rebuild or drag-copy, then reports `1.0.1` after relaunch.
3. On the built-in display, the update preserves Microphone, Accessibility, Input Monitoring, and Screen Recording grants, the OpenAI Keychain item, modes, history, and recordings. If macOS refuses continuity, do not claim the requirement passed; diagnose the signing or installation path.
4. A tampered ZIP, wrong Sparkle key, malformed feed, wrong bundle identifier, wrong signing identity, downgrade, missing asset, or wrong `gh` account never becomes a published update.
5. A failed publication leaves the previous latest release usable. No private content or key material is printed, committed, uploaded, or captured in QA evidence.
6. A completed multi-commit task produces one patch on the owner's release command. Repeating the command does not create a duplicate version; publishing the next task does not silently include an unrelated unreleased task.
7. After bootstrap, the owner can obtain the next version entirely through Whisper's interface. Agent documentation contains the build/release commands; the short owner guide requires none. Installation during synthetic active dictation/capture/processing is deferred and resumes safely when idle.
8. The Right Option/menu-stop report stays explicitly open under `WH-M6-014`. Compare pre/post-update availability without claiming to fix that baseline issue. Update-specific regressions block M7; the separately recorded baseline issue blocks M6 acceptance.

## Out of scope

- Notarization, Developer ID/App Store, support for other Macs, and bypassing macOS security prompts;
- GitHub Actions or an always-on local runner that releases without this Mac being invoked;
- beta channels, delta updates, staged rollout, rollback UI, and silent installation during active work;
- automatic major/minor version policy after the owner decides to leave 1.0.x.

## Sources

- [Sparkle setup and key guidance](https://sparkle-project.org/documentation/)
- [Sparkle update publishing and ZIP preservation](https://sparkle-project.org/documentation/publishing/)
- [Sparkle standard updater controller](https://sparkle-project.org/documentation/api-reference/Classes/SPUStandardUpdaterController.html)
- [Sparkle updater delegate and installation deferral](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)
- [GitHub stable latest-release asset links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [GitHub draft/latest release behavior](https://docs.github.com/en/rest/releases/releases)
