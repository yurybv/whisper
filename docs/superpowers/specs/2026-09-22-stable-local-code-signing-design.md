# Stable Local Code Signing Design

Date: 2026-09-22
Status: approved by owner on 2026-09-22
Audience: owner and implementation agent

## Goal

Sign every local Whisper package with one persistent, free identity so macOS can recognize rebuilt bundles as the same application on this Mac. The owner should grant Microphone, Accessibility, Input Monitoring, and Screen Recording access once after migration instead of repeating the setup after each build.

## Context

The current package is signed ad hoc with `codesign --sign -`. Its code-directory hash changes when the executable changes, it has no signing authority or TeamIdentifier, and macOS permission records can therefore stop matching after a rebuild. The repository currently has no valid code-signing identity in the login Keychain.

This is a personal one-Mac workflow. Public distribution, Apple notarization, the Mac App Store, and a paid Apple Developer membership remain outside scope.

## Considered approaches

### Persistent self-signed Code Signing identity — selected

Create one self-signed certificate and private key named `Whisper Local Development` in the owner's login Keychain. Trust that certificate for code signing on this Mac and reuse it for every package. This is free, local, compatible with the existing unsandboxed bundle, and does not require an Apple account.

Trade-offs: the identity is trusted only on this Mac; deleting or replacing the certificate invalidates the continuity; the app remains unnotarized; the first migration from the old ad-hoc build still requires one fresh permission grant and may require replacing the old Keychain item.

### Free Apple Development identity

Use an Xcode personal team to create an Apple Development certificate. This gives an Apple-issued development identity but requires Apple-ID/Xcode provisioning, can expire, and adds provisioning behavior that the local utility does not need. It is not selected.

### Continue ad-hoc signing

Keep the present package and document repeated permission repair. This cannot meet the requested one-time permission behavior and is rejected.

## Architecture

### Identity setup

Add an explicit, idempotent setup command for the owner. It creates the certificate and private key only when the exact identity is missing, imports them into the login Keychain, and trusts the certificate only for code signing. Temporary key, certificate, configuration, and PKCS#12 files are created in a private temporary directory and removed on exit. No password, private key, API key, or Keychain content is printed or committed.

The identity has these fixed properties:

- common name: `Whisper Local Development`;
- purpose: Code Signing;
- storage: the current user's login Keychain;
- validity: ten years;
- private key: imported as non-extractable and accessible to `/usr/bin/codesign` through Keychain policy;
- trust: local code-signing trust on this Mac, not system-wide web or email trust.

If the identity exists but is unusable, duplicated, expired, or lacks a private key, setup stops with a precise recovery message. It does not silently replace an existing identity.

### Packaging

`scripts/package.sh` resolves exactly one valid `Whisper Local Development` signing identity before deleting or building package output. Packaging fails early when the identity is absent or ambiguous. There is no automatic fallback to ad-hoc signing because such a fallback would silently invalidate macOS permissions.

The Release target remains built unsigned. After copying the validated arm64 bundle to `build/Whisper.app`, packaging signs the final bundle with the persistent identity and `--timestamp=none`, then runs strict verification. It also verifies:

- bundle identifier is exactly `dev.yury.whisper`;
- the signature is not ad hoc;
- the certificate common name is `Whisper Local Development`;
- the designated requirement is present;
- the arm64-only invariant remains unchanged.

`scripts/verify.sh` continues to call the canonical packaging script and therefore enforces the stable signature in the full release gate.

### Permission migration

The first stable-signed package is a new code identity relative to all previous ad-hoc builds. The owner performs one migration:

1. quit every old Whisper process;
2. build and launch the exact fixed-path `build/Whisper.app`;
3. remove stale Whisper entries only when macOS still reports access as missing;
4. add or enable the exact current bundle for Accessibility, Input Monitoring, and Screen Recording, and grant Microphone access;
5. save or replace the OpenAI key once if the prior ad-hoc Keychain ACL does not authorize the stable identity;
6. rebuild the app at the same path and confirm the permissions and saved key remain usable.

The application does not modify the TCC database, loosen Keychain ACLs, suppress consent, or automate System Settings.

## Repository changes

- Add `scripts/setup-local-signing.sh` for idempotent identity provisioning.
- Update `scripts/package.sh` to require and verify the persistent identity.
- Extend shell tests with missing, ambiguous, ad-hoc, wrong-authority, and successful signing cases.
- Update the packaging ADR, approved MVP distribution section, roadmap, README, testing strategy, release task records, and acceptance matrix.
- Add a Milestone 6 task for stable local signing and make final acceptance depend on it.

## Verification

Automated verification must prove:

- setup refuses malformed or conflicting identity state without replacing it;
- packaging fails before build output is deleted when the identity is missing or ambiguous;
- packaging never passes `-` as the signing identity;
- the packaged bundle passes strict signature verification and is not ad hoc;
- two independent clean packages have the same certificate chain and designated requirement;
- `./scripts/verify.sh` passes with the persistent identity;
- `git diff --check` passes and no private or secret material appears in Git.

Manual verification must use the built-in display and the exact `build/Whisper.app` path. After the one-time permission migration, rebuild twice and confirm Microphone, Accessibility, Input Monitoring, Screen Recording, global shortcuts, text insertion, meeting capture availability, and saved-key connection testing remain available without re-adding the application.

## Failure handling and recovery

- Missing identity: setup command is printed; packaging stops before rebuilding.
- Duplicate identity: packaging and setup stop with a repair message; neither silently selects nor replaces a certificate.
- Expired or untrusted identity: packaging stops with a repair instruction; it never falls back to ad hoc.
- Lost private key: create a replacement identity deliberately, then repeat the one-time permission migration.
- Certificate backup or transfer is outside this task; the certificate remains local to this Mac.

## Out of scope

- Developer ID, Apple notarization, App Store distribution, provisioning profiles, and automatic updates;
- bypassing Gatekeeper or macOS permission prompts;
- editing TCC databases or granting permissions programmatically;
- exporting the private key or installing the identity on another Mac;
- changing the bundle identifier, sandbox model, entitlements, storage paths, or application behavior.
