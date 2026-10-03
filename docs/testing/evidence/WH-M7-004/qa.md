# WH-M7-004 bootstrap update QA

## Preparation checkpoint — 2026-10-03

- Environment: Apple Silicon MacBook Pro, built-in display, macOS 26.4.1, Xcode 26.6 (17F113), Swift 6.3.3, macOS SDK 26.5, XcodeGen 2.46.0.
- Scope prepared: one verified public `1.0.0` installation at `/Applications/Whisper.app`, followed by an in-app Sparkle update to public `1.0.1`, continuity comparison, isolated failure fixtures, and owner instructions.
- Source state: `WH-M7-001` through `WH-M7-003` are done on `origin/master`; this Task 4 documentation checkpoint will become the `initial` bootstrap source after review verification and push.
- Automated baseline: the canonical gate passes 330 unit/service tests and 17 UI tests, signed Release packaging, and strict nested-signature verification. Release feed tests reject tampered archive, wrong key, wrong URL/version/length, multiple enclosures, external notes, and malformed XML. Release workflow tests pass every remote mutation/retry boundary and bootstrap-order guard.
- Publication/installation: not run. No tag, GitHub Release, public asset, or `/Applications/Whisper.app` replacement is created by this preparation checkpoint.
- Known limitation: the Right Option/menu-start-stop report remains unresolved and separately assigned to `WH-M6-014`; early releases are personal testing builds, not completed MVP acceptance.

## Privacy review

- Documentation records only tool versions, pass counts, task/version identifiers, paths, hashes/fingerprints intended for release provenance, and generated state identifiers.
- No OpenAI key, Keychain value, signing private key, Authorization header, user dictation, transcript, recording content, custom instruction, clipboard content, or raw test bundle is committed or published.
- Live evidence must continue using state-only observations and generated fixtures. Public assets are limited to the signed app ZIP, appcast, and sanitized release manifest.

## Live bootstrap evidence

Pending explicit authorization for the bootstrap pair. Record exact source SHAs, versions, public release links, artifact digests/signatures, installed-path/version observations, continuity states, isolated failure results, and any OS-controlled confirmation after execution. Do not replace pending rows with passes unless directly observed.
