# WH-M6-002 verification-command QA

Date: 2026-09-15

Host: Apple Silicon, macOS 26.4.1

Toolchain: Xcode 26.6 (17F113), Swift 6.3.3, macOS SDK 26.5, XcodeGen 2.46.0

## TDD evidence

- `bash Tests/Scripts/VerifyScriptTests.sh` initially failed with `scripts/verify.sh must exist and be executable`.
- After implementation it passed five contract checks: named required stages, unit/UI test selection, explicit UI skip behavior, required-stage fail-fast behavior, privacy-pattern rejection, and unknown-option rejection.

## Clean verification runs

`./scripts/verify.sh --skip-ui-tests` passed twice. Each run:

- removed and regenerated `Whisper.xcodeproj` and `build/VerificationDerivedData`;
- passed environment, repository diff, privacy-pattern, shell syntax, and shell behavior checks;
- built the application plus unit and UI-test products;
- executed 293 unit/service tests with zero failures;
- produced the deterministic `build/Whisper.app` Release bundle;
- passed `codesign --verify --deep --strict`.

ShellCheck was unavailable, so the named lint stage explicitly fell back to `bash -n` for every repository shell script.

## Explicit exception

UI-test execution was skipped with the script's documented `--skip-ui-tests` option because the owner requested no cursor/focus interference while working. The UI-test target was still compiled. The default script path and its UI-test selection passed the isolated shell contract test; a real UI run remains required by the final release acceptance gate.
