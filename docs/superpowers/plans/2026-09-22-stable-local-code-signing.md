# Stable Local Code Signing Implementation Plan

Implementation status (2026-09-22): code, local identity provisioning, two clean-package comparison, and the full automated verification gate passed. The task remains in review until the owner confirms macOS permission continuity after the one-time migration.

> **For agentic workers:** Implement inline task by task. Use a failing shell test before changing packaging behavior, and run the repository verification gate before delivery.

**Goal:** Keep Whisper's macOS code identity stable across local rebuilds with one free certificate in the owner's login Keychain.

**Architecture:** A setup script creates one self-signed Code Signing identity in the login Keychain. A shared resolver gives packaging the identity fingerprint and refuses missing or ambiguous identities. The Release bundle is signed with that fingerprint and checked for a non-ad-hoc signature and designated requirement.

**Tech Stack:** Bash, macOS `security` and `codesign`, OpenSSL, XcodeGen, Xcode, SwiftUI UI tests.

## Global constraints

- Bundle identifier stays `dev.yury.whisper` and the output path stays `build/Whisper.app`.
- The signing certificate and private key never enter Git, test fixtures, or command output.
- The private key is imported as non-extractable; trust is scoped to Code Signing in the user domain.
- Packaging never falls back to `codesign --sign -`.
- Existing user data and macOS permission records are not deleted by scripts.
- UI automation runs only on the built-in display.

## Files

- `scripts/setup-local-signing.sh`: idempotent certificate/key creation and trust setup.
- `scripts/local-signing-identity.sh`: exact identity lookup and validation shared by setup and packaging.
- `scripts/package.sh`: early identity guard, stable signing, and signature verification.
- `Tests/Scripts/PackageScriptTests.sh`: missing and ambiguous identity regressions.
- `Tests/Scripts/LocalSigningIdentityTests.sh`: exact resolver behavior.
- `docs/architecture/adr/0002-ship-an-unsandboxed-ad-hoc-build.md`, `README.md`, `docs/implementation/task-backlog.md`, `docs/implementation/tasks/m6-release.md`, `docs/implementation/roadmap.md`, `docs/testing/test-strategy.md`, and `docs/testing/release-acceptance.md`: decision, workflow, and evidence.

---

### Task 1: Enforce the persistent identity in packaging

- [ ] Add a shell regression that mocks `security find-identity` with zero matching identities and confirms `scripts/package.sh` stops before `xcodegen` or deletion of an existing package.
- [ ] Run the regression and confirm it fails because the current package script proceeds to ad-hoc signing.
- [ ] Add exact identity resolution for one valid `Whisper Local Development` SHA-1 fingerprint in the login Keychain. Reject zero or multiple matches.
- [ ] Sign with the fingerprint. Verify the package with `codesign --verify --deep --strict`, inspect `codesign -dv` for `Signature=adhoc` absence and the expected authority, and require a designated requirement from `codesign -dr -`.
- [ ] Run focused shell tests and confirm the missing, duplicate, and valid identity paths pass.

### Task 2: Provision the local identity

- [ ] Add a shell regression for idempotent setup: an existing valid identity is reused without creating a new key; an existing conflicting certificate is rejected.
- [ ] Run the regression and confirm the setup command is missing.
- [ ] Implement `scripts/setup-local-signing.sh`: create temporary RSA key and ten-year self-signed Code Signing certificate in a `0700` temporary directory; import the private key as non-extractable into the login Keychain for `/usr/bin/codesign`; add user trust for the `codeSign` policy; remove temporary files on exit.
- [ ] Run the focused tests, then run setup on the owner's Mac and confirm `security find-identity -v -p codesigning` returns exactly one matching identity.

### Task 3: Prove stable package identity and update documentation

- [ ] Package twice from clean Release builds. Confirm both bundles share the same certificate fingerprint and textual designated requirement while their code-directory hashes may differ.
- [ ] Run `./scripts/verify.sh`; it must pass build, 316 unit tests, 17 UI tests on the built-in display, package signing, and final signature verification.
- [ ] Update the source-of-truth task record and backlog with a scoped WH-M6-013 task and evidence. Update the roadmap, ADR, README, test strategy, and release acceptance notes so they describe the new local signing workflow and the first-time permission migration accurately.
- [ ] Run `git diff --check`, inspect the complete diff and tracked files for key/certificate material, commit with a Conventional Commit message, run the `yurybv` account/remote/branch/status guard, push to `origin/master`, and confirm zero divergence.

## Manual owner check

After the first signed launch, the owner grants any requested permissions once, then relaunches a rebuilt `build/Whisper.app` at the same path. The acceptance result is whether Microphone, Accessibility, Input Monitoring, Screen Recording, shortcuts, insertion, and saved-key access remain available without re-adding the app. Automated signature stability does not substitute for this real macOS permission check.
