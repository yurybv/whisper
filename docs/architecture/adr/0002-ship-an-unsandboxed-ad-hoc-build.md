# ADR 0002: Ship an unsandboxed ad-hoc build

- Status: Superseded for local signing by the 2026-09-22 stable-signing decision below
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

Whisper is a personal utility installed on one owned Mac. It observes global keyboard events, works with the focused element of other applications, and captures microphone and system audio after explicit macOS permission grants. App Store distribution, Developer ID signing, notarization, automatic updates, and multi-user delivery are outside the MVP.

## Decision

Build the app with App Sandbox disabled, an empty entitlement dictionary, and the required privacy usage descriptions. Package and sign the local bundle ad hoc with `codesign --sign -`. Install it outside the Mac App Store and document the first-launch Gatekeeper flow, including right-clicking the app and choosing Open when required.

Microphone, Screen Recording, and Accessibility remain explicit runtime permissions. Unsandboxed execution does not bypass user consent or permission checks.

## Consequences

- The personal build can use the approved system-integration architecture without adding store-distribution work.
- The user must accept macOS permission prompts and may see an unnotarized-app warning.
- The bundle is appropriate only for controlled personal installation; it is not a public release artifact.
- Packaging must verify the exact bundle identifier and ad-hoc signature before installation.

## Rejected alternatives

- Mac App Store sandboxing: rejected for the MVP because store submission and sandbox compatibility work expand scope beyond a one-Mac tool.
- Developer ID signing and notarization: rejected as post-MVP distribution work requiring credentials and an Apple Developer workflow.
- An unsigned bundle: rejected because deterministic ad-hoc signing provides a clearer local packaging and verification path.

## References

- [Apple code-signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html)
- [Approved distribution design](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#distribution)

## 2026-09-22 local-signing amendment

The owner requested permission grants that survive local rebuilds. Ad-hoc signatures are therefore no longer used for new packages: their code identity changes with each binary. The unsandboxed, one-Mac, unnotarized distribution choice remains. `scripts/setup-local-signing.sh` provisions one self-signed `Whisper Local Development` identity in the login Keychain, and `scripts/package.sh` requires that exact valid identity, with no ad-hoc fallback. The first migration from an older ad-hoc app still needs a fresh macOS permission grant; subsequent packages reuse the same signing identity and bundle identifier. See the [approved signing design](../../superpowers/specs/2026-09-22-stable-local-code-signing-design.md). This does not make the app a trusted Developer ID or notarized distribution build.
