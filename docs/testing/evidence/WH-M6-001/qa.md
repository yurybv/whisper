# WH-M6-001 Packaging verification

Date: 2026-09-15. Mac: Apple Silicon, macOS 26.4.1, Xcode 26.6, macOS SDK 26.5.

## Environment rejection tests

`bash Tests/Scripts/PackageScriptTests.sh` passed four isolated PATH-based cases:

- x86_64 is rejected with the Apple Silicon requirement;
- Xcode 25.4 is rejected with the Xcode 26.6 minimum;
- macOS SDK 14.5 is rejected with the macOS 15 SDK minimum.
- a symlinked `build` root is rejected before cleanup or generation can write outside the repository.

The mocks stop before project generation or build and access no user data.

## Clean package smoke

`./scripts/package.sh` completed twice. Each run regenerated `Whisper.xcodeproj`, removed only `build/DerivedData` and `build/Whisper.app`, built Release for arm64, copied the bundle to the fixed output, applied a timestamp-free ad-hoc signature, and verified it deeply and strictly.

Both clean runs produced an identical sorted SHA-256 manifest for every file in `build/Whisper.app`. Final bundle checks:

- path: `build/Whisper.app`;
- bundle identifier: `dev.yury.whisper`;
- executable architecture: `arm64` only;
- signature: ad hoc, no TeamIdentifier;
- `codesign --verify --deep --strict`: PASS;
- `bash -n` for both packaging scripts and their test: PASS;
- ShellCheck: unavailable on this Mac.

The packaged app was not launched under the owner's no-cursor/no-interference instruction. Live Gatekeeper and application-launch checks remain explicitly assigned to `WH-M6-003`; this smoke did not open a window, change permissions, read production history, or access Keychain/network data.
