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

## Live bootstrap evidence — 2026-11-08

- Authorization: the owner explicitly requested that the bootstrap pair be published, installed, and tested.
- Initial source: `WH-M7-004`, `40e75ed6b9b9cba8d63f17a5f9983bbd1a58e280`, bootstrap phase `initial`, version `1.0.0`.
- Initial artifacts: the sealed ZIP SHA-256 is `12b028427def5f56f81635934aed40d4104ea7b9a49ee9a7bcb92d72ab9e7caa`; the signing certificate fingerprint is `3918f34830aa1c4307777059bc515ccb72620601`; the Sparkle public-key fingerprint is `2d409331d673008bbfeb5d3036b36b624c79534b94f046caa2138c6d979f885c`.
- Publication: [v1.0.0](https://github.com/yurybv/whisper/releases/tag/v1.0.0) is public with ZIP, appcast, and sanitized manifest assets. Fresh public downloads matched the sealed local artifacts byte-for-byte, and the extracted arm64 bundle passed strict nested signature and designated-requirement verification.
- Installation: the verified public `1.0.0` bundle is installed at `/Applications/Whisper.app`; the prior bundle is retained as `/Applications/Whisper.pre-bootstrap-20261108-224141.app`. Installed metadata reports `dev.yury.whisper` version `1.0.0`, the strict signature passes, and the executable launched.
- Pre-update continuity: Microphone, Accessibility, Input Monitoring, and Screen Recording are granted for `dev.yury.whisper`; the named OpenAI Keychain item is present without reading its value; three mode identifiers are present. History contains zero dictation and zero meeting rows. Eight owned recording directories remain, but no audio was opened and no matching meeting row is present, so generated history/recording continuity remains pending.
- Pending before the second checkpoint closes: owner confirmation that Settings shows `1.0.0` and exposes **Check for Updates…**; public `1.0.1`; the standard Sparkle update/relaunch; post-update continuity; generated history/recording fixtures; isolated failure and busy-state checks.
