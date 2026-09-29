# Local Automatic Updates Design

Date: 2026-09-29

Status: owner-selected direction; implementation pending

Audience: owner and implementation agent

## Goal

Install Whisper once, then let the installed macOS app discover and install later signed releases without rebuilding it on the owner's Mac. Start at `1.0.0`; use `v1.0.0`, `v1.0.1`, and subsequent Git tags as the release-version source of truth. A release for each subsequent delivered commit advances the patch number by one while the owner chooses to remain on the 1.0 line.

This is an owner-requested post-MVP expansion. The current approved MVP explicitly excludes automatic updates; this document does not change the unfinished Milestone 6 acceptance gate.

## Current constraints

- Whisper is an unsandboxed, Apple Silicon macOS 15+ menu-bar app with bundle identifier `dev.yury.whisper`.
- `scripts/package.sh` builds an unsigned Release bundle and signs its final copy with the persistent, self-signed `Whisper Local Development` identity in this Mac's login Keychain. The signing private key was imported as non-extractable and must stay on this Mac.
- `Resources/Info.plist` currently contains static `1.0`/`1` values, and Settings displays a hard-coded version. Neither can identify releases correctly.
- The repository uses XcodeGen and `scripts/verify.sh`; generated Xcode projects are not source of truth.
- GitHub repository `yurybv/whisper` is public. The active `gh` account may currently be different. No code, tag, release, or remote operation is authorized by this planning document.

## Selected design

### Update client

Use a pinned stable Sparkle 2 release through XcodeGen's Swift Package dependency. Start `SPUStandardUpdaterController` programmatically in the normal app lifecycle, retain it for the process lifetime, and expose **Check for Updates…** in the menu-bar UI. Sparkle performs periodic background checks and presents its standard update/installation UI; it does not silently replace the app during dictation or recording. Settings/About reads the version from the installed bundle rather than a literal string.

The released bundle contains:

- `SUFeedURL = https://github.com/yurybv/whisper/releases/latest/download/appcast.xml`;
- the public Sparkle EdDSA key in `SUPublicEDKey`;
- matching `CFBundleShortVersionString` and `CFBundleVersion`, starting at `1.0.0`.

Development builds with the non-release `0.0.0` version must not start the updater or display a misleading update error. The public key is not secret; Sparkle's private EdDSA key remains in the local login Keychain and never enters Git, a GitHub secret, a log, or a release. Use Sparkle's `generate_keys` once and `generate_appcast` for each release. Pin Sparkle to an exact version in the tracked XcodeGen specification.

### Version and release identity

Git tags identify published releases, not a version literal committed to Swift code. The local release command derives the candidate from the latest published `v1.0.PATCH` tag (first release `v1.0.0`, next `v1.0.1`) and injects it into both Info.plist version keys **before** final code signing. It verifies that the bundled version, appcast version, tag, asset name, and release title agree. A normal development package retains a clearly non-release version and is never published.

For the requested “one patch per commit” discipline after `v1.0.0`, the release command refuses to publish if zero or more than one `master` commit exists after the last release tag. Thus a missed release is visible instead of silently assigning one patch to several commits. The initial `v1.0.0` release is a deliberate bootstrap exception. The command does not itself create a source-code commit.

### Hosting and publication

The owner runs one local release command on this Mac after a verified commit reaches `origin/master`. It packages with the existing local certificate, creates `Whisper-1.0.PATCH.zip` with `ditto` (preserving framework symlinks), generates an `appcast.xml` whose ZIP enclosure carries Sparkle's EdDSA signature, and uploads both to a **draft** GitHub Release for the exact tag. The feed itself is not additionally signed in this first version. Only after the assets and public URLs are verified does it publish that release as `latest`. The stable feed URL above then resolves to the new appcast; each appcast enclosure points to its own exact tagged ZIP URL. No GitHub Pages site, separate installer server, GitHub-hosted signing key, or paid Apple Developer membership is needed.

The script is fail-closed and idempotent: it refuses the wrong `gh` account, remote, branch, dirty tree, diverged `origin/master`, missing/changed signing identities, missing Sparkle key, existing release/tag/asset conflict, malformed/unsigned feed, or URL/version mismatch. It never overwrites an existing published release. If publication fails before the draft is published, the previous latest release and feed remain live; a draft can be inspected and resumed or removed explicitly. Local staging is outside the tracked source tree and must not contain user recordings or credentials.

There is **no automatic cloud build on every push**. The existing non-extractable signing key cannot be used by a GitHub-hosted runner. Publishing still requires this Mac to run the release command. A permanently running self-hosted runner is a possible later automation, not part of the first implementation.

### Signing, installation, and migration

Preserve the same app bundle identifier, app path, local certificate, and designated requirement across updates. Add explicit verification for Sparkle's embedded framework and helpers; the present `codesign --deep --sign` packaging must be audited and adjusted as needed rather than assumed sufficient. An update archive must be EdDSA signed and served over HTTPS. GitHub's public Release ZIP is an app archive, not a GitHub source ZIP.

The first `1.0.0` release must be installed manually because older Whisper builds do not contain an updater. Install that released ZIP's `Whisper.app` at the fixed `/Applications/Whisper.app` path, complete any one-time Gatekeeper/permission migration, and then verify `1.0.0 → 1.0.1` with the same signing identity. A self-signed certificate is trusted only on the owner's Mac: this is not a notarized public distribution solution. Losing or replacing either the app-signing key or Sparkle EdDSA key can break update continuity and requires an explicit recovery procedure; never rotate either silently.

## Acceptance

1. A fresh `1.0.0` release shows version `1.0.0` and can check the public feed.
2. With `v1.0.1` published, the installed `1.0.0` app offers and installs `1.0.1` without a manual rebuild or drag-copy, then reports `1.0.1` after relaunch.
3. On the built-in display, the update preserves Microphone, Accessibility, Input Monitoring, and Screen Recording grants, the OpenAI Keychain item, modes, history, and recordings. If macOS refuses continuity, do not claim the requirement passed; diagnose the signing or installation path.
4. A tampered ZIP, wrong Sparkle key, malformed feed, wrong bundle identifier, wrong signing identity, downgrade, missing asset, or wrong `gh` account never becomes a published update.
5. A failed publication leaves the previous latest release usable. No private content or key material is printed, committed, uploaded, or captured in QA evidence.

## Out of scope

- Notarization, Developer ID/App Store, support for other Macs, and bypassing macOS security prompts;
- GitHub Actions or an always-on local runner that releases without this Mac being invoked;
- beta channels, delta updates, staged rollout, rollback UI, and silent installation during active work;
- automatic major/minor version policy after the owner decides to leave 1.0.x.

## Sources

- [Sparkle setup and key guidance](https://sparkle-project.org/documentation/)
- [Sparkle update publishing and ZIP preservation](https://sparkle-project.org/documentation/publishing/)
- [Sparkle standard updater controller](https://sparkle-project.org/documentation/api-reference/Classes/SPUStandardUpdaterController.html)
- [GitHub stable latest-release asset links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [GitHub draft/latest release behavior](https://docs.github.com/en/rest/releases/releases)
