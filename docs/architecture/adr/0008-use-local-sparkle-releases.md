# ADR 0008: Use agent-operated local Sparkle releases

- Status: Accepted
- Date: 2026-10-03

## Context

Whisper is a personal macOS utility for one owned Mac. Its stable self-signed code-signing identity and non-extractable private key live only in that Mac's login Keychain. The owner wants one initial installation and then in-app updates without recurring build or file-copy work. GitHub Actions cannot reproduce the local identity, while source pushes alone must not publish executable artifacts.

ADR 0002 excluded automatic updates from the earlier MVP packaging decision. The owner-approved update-first plan now adds a narrowly scoped personal-testing channel while keeping notarized or multi-Mac distribution out of scope.

## Decision

- Pin Sparkle 2 and use its standard update UI and EdDSA archive signatures.
- Build, verify, sign, and publish releases only from the owner's Mac through the guarded prepare/publish workflow.
- Host immutable ZIP, appcast, and sanitized provenance manifest assets on GitHub Releases. The latest release's appcast is the stable feed; each enclosure targets its exact tagged ZIP.
- Keep both signing private keys in the login Keychain. Publish only the Sparkle public key and non-secret certificate/key fingerprints needed for provenance checks.
- Install the verified public `1.0.0` bundle once at `/Applications/Whisper.app`; require `1.0.1` and later versions to arrive through Sparkle for update acceptance.
- Preserve bundle identifier, installation path, certificate, and designated requirement. Defer installation whenever active work could be lost.
- Require an explicit owner release command before tags, releases, assets, or installed-app replacement. Preparation remains local and read-only with respect to GitHub.

## Consequences

- The owner's recurring workflow is limited to requesting a release, invoking **Check for Updates…**, and accepting standard macOS/Sparkle UI when safe.
- The signing Mac must be available for publication; there is no unattended cloud release path.
- Releases are personal, self-signed, and not notarized. Gatekeeper or Keychain may require local confirmation, and this design must never weaken macOS security controls.
- Published assets are immutable. Interrupted publication resumes from the sealed local manifest; conflicts stop rather than overwrite or rotate versions/keys.
- A real `1.0.0 → 1.0.1` installed update plus permission/data continuity is required before the update channel is considered ready. Automated feed and controller tests alone are insufficient.
- The update channel does not certify overall MVP readiness or resolve the separate Right Option/menu-start-stop report.

## Rejected alternatives

- GitHub Actions: cannot access the persistent non-extractable local signing identity and would add secret-hosting/runner scope.
- Manual ZIP download and app replacement for every version: fails the owner's no-recurring-copy goal and cannot prove Sparkle works.
- GitHub Pages or a custom update server: adds hosting without improving the single-Mac workflow.
- Developer ID/notarization or App Store delivery: requires paid credentials and expands beyond the approved personal MVP.
