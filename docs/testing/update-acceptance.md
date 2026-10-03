# Whisper automatic update acceptance

Overall result: **PENDING — no public bootstrap release has been authorized or installed**

Date started: 2026-10-03

Environment: Apple Silicon MacBook Pro; built-in display; macOS 26.4.1; Xcode 26.6 (17F113); Swift 6.3.3; macOS SDK 26.5; XcodeGen 2.46.0.

Target flow: verified public `1.0.0` ZIP → one installation at `/Applications/Whisper.app` → public `1.0.1` through installed `1.0.0` and Sparkle's standard UI.

Evidence policy: use generated identifiers and state labels only. Never record an API key, private dictation, transcript, recording contents, custom instructions, Authorization value, clipboard contents, or private key material. `PASS` requires the exact live step unless the row explicitly says automated. `AUTOMATED PASS / LIVE NOT RUN` is useful evidence but does not satisfy the installed-update gate. `PENDING` is never an inferred pass.

Known baseline: the owner-reported Right Option/menu-start-stop issue remains unresolved under `WH-M6-014`. Record whether it is still available before and after the update, but do not classify that baseline as fixed or caused by Sparkle without separate evidence.

## Public release and installation

| ID | Case | Result | Required evidence |
|---|---|---|---|
| U-01 | `1.0.0` prepared from the Task 4 review checkpoint | PENDING | Local sealed manifest records exact `origin/master` SHA, task, version, included commits, signing fingerprints, artifact sizes/hashes, and successful verification. |
| U-02 | Public `v1.0.0` release is internally consistent | PENDING | Latest/tag identity, public ZIP/appcast/manifest bytes, SHA-256 values, enclosure signature/length/URL, bundle ID, both versions, arm64, and nested code signatures all agree. |
| U-03 | Public `1.0.0` installs once at the fixed path | PENDING | Prior app is preserved recoverably; the downloaded public ZIP—not a rebuilt bundle—is installed at `/Applications/Whisper.app`; launch and Settings show `1.0.0`. |
| U-04 | Installed `1.0.0` can check the public feed | PENDING | Both menu-bar and Settings actions are available; a check completes without making the app unusable. |
| U-05 | `1.0.1` prepared and published from the second Task 4 checkpoint | PENDING | Newer exact source; same signing identities; verified public ZIP/appcast/manifest; `v1.0.1` is latest and enclosure targets its exact tagged ZIP. |
| U-06 | Installed `1.0.0` offers `1.0.1` | PENDING | **Check for Updates…** presents the standard Sparkle update UI from the installed `1.0.0` copy. |
| U-07 | Sparkle installs and relaunches `1.0.1` | PENDING | No manual copy; standard install/relaunch completes; `/Applications/Whisper.app` and Settings both report `1.0.1`. |
| U-08 | Periodic checking remains available | PENDING | With the public feed healthy, background-check configuration remains enabled without forcing an update during active work. |

## Identity, permissions, and data continuity

Record only state (`granted`, `not granted`, `present`, `missing`) and generated identifiers. Do not record secret or user-content values.

| ID | Case | Result | Required evidence |
|---|---|---|---|
| C-01 | Bundle identity and installation path | PENDING | `dev.yury.whisper` at `/Applications/Whisper.app` before and after. |
| C-02 | Code-signing certificate and designated requirement | PENDING | Certificate fingerprint and requirement match across public `1.0.0`, installed `1.0.0`, and installed `1.0.1`; all nested code verifies. |
| C-03 | Microphone grant | PENDING | Named permission state observed before and after on the built-in display. |
| C-04 | Accessibility grant | PENDING | Named permission state observed before and after. |
| C-05 | Input Monitoring grant | PENDING | Named permission state observed before and after. |
| C-06 | Screen Recording grant | PENDING | Named permission state observed before and after. |
| C-07 | OpenAI Keychain item availability | PENDING | Presence/readability state survives without revealing or replacing the key. |
| C-08 | Modes | PENDING | Generated built-in/custom mode identifiers present before and after; no instructions recorded. |
| C-09 | History | PENDING | Generated dictation and meeting record identifiers present before and after; no text recorded. |
| C-10 | Recordings | PENDING | Generated recording identifier/path ownership and playback availability preserved; no audio opened for evidence. |
| C-11 | Right Option/menu-start-stop baseline | PENDING | Availability compared before/after, with root cause and acceptance still assigned to `WH-M6-014`. |

## Failure and busy-state isolation

| ID | Case | Result | Required evidence |
|---|---|---|---|
| F-01 | Tampered ZIP or enclosure length | AUTOMATED PASS / LIVE NOT RUN | Feed/artifact tests reject changed archive bytes and wrong length. Repeat against the isolated fixture installed copy and prove the prior app remains. |
| F-02 | Wrong EdDSA key or signature | AUTOMATED PASS / LIVE NOT RUN | Feed/artifact tests reject the wrong key/signature. Repeat only against the isolated fixture feed. |
| F-03 | Malformed feed, external notes, multiple enclosure, or bad URL/version | AUTOMATED PASS / LIVE NOT RUN | Parser tests reject every shape. Repeat the user-visible failure against the isolated fixture feed. |
| F-04 | Downgrade and offline check | PENDING | Isolated fixture rejects a lower version; offline check leaves the installed test copy usable and unchanged. |
| F-05 | Active work defers installation and idle resumes | AUTOMATED PASS / LIVE NOT RUN | Updater-controller tests cover dictation/capture/finalization/processing gates. Confirm with generated live fixture state. |
| F-06 | Interrupted publication preserves/resumes remote state | AUTOMATED PASS | Release-script tests cover tag, draft, each upload, publish, and idempotent retry boundaries without overwriting assets. |

## Completion rule

`WH-M7-004` remains in `review` until U-01 through U-08, C-01 through C-11, and live portions of F-01 through F-05 have explicit results with no update-specific regression. Final evidence belongs in `docs/testing/evidence/WH-M7-004/qa.md`. Successful updater QA does not complete the separate MVP acceptance matrix.
