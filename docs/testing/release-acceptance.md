# Whisper MVP release acceptance

Overall result: **BLOCKED — consolidated physical dictation, mode, recovery, and remaining macOS-dialog acceptance remains pending**

Date: 2026-09-30

Environment: Apple Silicon MacBook Pro; macOS 26.4.1; Xcode 26.6 (17F113); Swift 6.3.3; macOS SDK 26.5; XcodeGen 2.46.0.

Build under test: 2026-09-30 `origin/master` at `538a294`; stable-local-identity `build/Whisper.app`; bundle identifier `dev.yury.whisper`; arm64.

Evidence policy: generated phrases only; no real API key, private dictation, transcript, custom instruction, Authorization value, or user document is recorded. `PASS` means the exact row has current or named prior evidence. `AUTOMATED PASS / LIVE NOT RUN` records useful coverage but does not satisfy the manual release gate. `NOT RUN` is an explicit release blocker, never an inferred pass.

## Dictation matrix

| ID | Case | Result | Evidence and remaining live check |
|---|---|---|---|
| D-01 | TextEdit, Default English | PASS (prior live) | The production pipeline inserted generated English into TextEdit in the Milestone 2 review. Repeat on the current packaged commit. |
| D-02 | TextEdit, Default Russian | PASS (prior live) | The production pipeline inserted generated Russian into TextEdit in the Milestone 2 review. Repeat on the current packaged commit. |
| D-03 | TextEdit, Russian-to-English custom mode | PASS (prior live) | The production pipeline inserted the translated generated fixture into TextEdit in the Milestone 2 review. Repeat on the current packaged commit. |
| D-04 | Notes insertion, all three language/mode cases | NOT RUN | A fixed-marker insertion smoke passed previously, but the current packaged end-to-end dictation flow must run in Notes. |
| D-05 | Safari insertion, all three language/mode cases | NOT RUN | A fixed-marker insertion smoke passed previously, but the current packaged end-to-end flow must run in a Safari text field. |
| D-06 | VS Code insertion, all three language/mode cases | NOT RUN | Requires a current packaged-app foreground session. |
| D-07 | Silent input makes no OpenAI request | AUTOMATED PASS / LIVE NOT RUN | `SilenceDetectorTests` and `DictationCoordinatorTests` cover the no-request path; confirm with the packaged app and a sanitized silent recording. |
| D-08 | Escape cancels push-to-talk | AUTOMATED PASS / LIVE NOT RUN | Hotkey, coordinator, recorder, and HUD tests pass; confirm with the physical shortcut. |
| D-09 | Offline recovery | AUTOMATED PASS / LIVE NOT RUN | Retry and retained-session tests plus WH-M5-003 offline evidence pass; confirm with network disabled during a generated dictation. |
| D-10 | Invalid-key recovery | AUTOMATED PASS / LIVE NOT RUN | OpenAI, safe-error, Settings, and onboarding fixtures pass; confirm with a disposable invalid fixture, never a real key in evidence. |
| D-11 | Revoked Microphone permission | AUTOMATED PASS / LIVE NOT RUN | Permission and Home/Recordings model fixtures pass; current macOS permission revocation/recovery is pending. |
| D-12 | Revoked Accessibility and clipboard fallback | AUTOMATED PASS / LIVE NOT RUN | `TextInsertionServiceTests` cover manual-paste fallback and clipboard preservation; current macOS revocation/recovery is pending. |
| D-13 | Active meeting rejects push-to-talk with a clear message | AUTOMATED PASS / LIVE NOT RUN | Hotkey routing, coordinator, menu-bar, and Recordings tests pass; confirm with physical push-to-talk during a real capture. |
| D-14 | Warp insertion after translated dictation | TARGET INSERTION PASS / PHYSICAL PTT NOT RUN | Implementation commit `8d2255d` routes captured bundle `dev.warp.Warp-Stable` through the production paste fallback. On 2026-09-30 a fixed generated marker was inserted into an isolated Warp prompt: the captured bundle matched, the result was `pasted`, the marker was present, and every prior pasteboard representation was restored. The same production service then inserted a separate fixed marker directly into a temporary TextEdit document under bundle `com.apple.TextEdit`, with the marker present and pasteboard unchanged. No marker value, clipboard value, credential, or user content is retained here. The physical Push-to-Talk and real-provider repetition remains in consolidated final task `WH-M6-003`. |

## Meeting matrix

| ID | Case | Result | Evidence and remaining live check |
|---|---|---|---|
| M-01 | Microphone and system audio saved separately | AUTOMATED PASS / LIVE NOT RUN | ScreenCaptureKit writer tests verify distinct durable outputs; capture and play a sanitized real two-source sample. |
| M-02 | Start and live timer/meters | AUTOMATED PASS / LIVE NOT RUN | Recordings model, menu-bar, and overlay tests plus offscreen WH-M4-005 screenshots pass; observe the current package. |
| M-03 | Stop and durable finalization | AUTOMATED PASS / LIVE NOT RUN | Recorder/coordinator tests pass; stop a real sanitized capture and inspect both files. |
| M-04 | Cancel | AUTOMATED PASS / LIVE NOT RUN | Recorder/coordinator/model cancellation tests pass; confirm with the current package. |
| M-05 | Low-disk block at 2 GB | AUTOMATED PASS / LIVE NOT RUN | Disk monitor and Recordings model boundary tests pass; exercise the packaged diagnostic fixture. |
| M-06 | Microphone loss | AUTOMATED PASS / LIVE NOT RUN | Capture failure tests preserve available output; disconnect or replace a disposable input during capture. |
| M-07 | Screen-capture revocation | AUTOMATED PASS / LIVE NOT RUN | Capture failure tests preserve microphone output; revoke and restore the current package permission. |
| M-08 | Relaunch while captured | AUTOMATED PASS / LIVE NOT RUN | Recovery-service/coordinator tests pass; terminate and reopen the current package with a sanitized captured job. |
| M-09 | Relaunch while transcribing | AUTOMATED PASS / LIVE NOT RUN | Durable manifest and recovery tests pass; repeat against a sanitized current-package job. |
| M-10 | Relaunch while processing | AUTOMATED PASS / LIVE NOT RUN | Processing recovery and stable instruction-snapshot tests pass; repeat against a sanitized current-package job. |
| M-11 | Synthetic three-hour input and bounded memory | PASS (current automated) | The real AVFoundation exporter test creates a 10,800-second sparse asset, produces nine chunks, enforces 20 MB, and limits peak growth to 64 MiB; it passed within the 293-test verification run. |
| M-12 | Chronological You/Others transcript | AUTOMATED PASS / LIVE NOT RUN | Transcript merge, overlap, and History presentation tests pass; inspect a sanitized two-source current-package result. |
| M-13 | Processed result | AUTOMATED PASS / LIVE NOT RUN | Processing coordinator and History detail tests pass; inspect a sanitized real result. |
| M-14 | Retry after failure | AUTOMATED PASS / LIVE NOT RUN | WH-M5-003 focused recovery tests pass and retain sources; trigger and recover a packaged offline failure. |
| M-15 | Reprocess without re-recording | AUTOMATED PASS / LIVE NOT RUN | Coordinator and History action tests pass idempotently; confirm from packaged History. |
| M-16 | Playback | AUTOMATED PASS / LIVE NOT RUN | Source validation, corruption rejection, mix selection, and cancellation tests pass; listen to sanitized packaged sources. |
| M-17 | Text export | AUTOMATED PASS / LIVE NOT RUN | Privacy-minimized atomic export tests pass; export a sanitized packaged result. |
| M-18 | Confirmed delete | AUTOMATED PASS / LIVE NOT RUN | Scoped record/file cleanup, tombstone retry, traversal, and symlink tests pass; delete one disposable packaged item. |

## UI and accessibility matrix

| ID | Case | Result | Evidence and remaining live check |
|---|---|---|---|
| U-01 | Keyboard-only navigation and visible focus | PASS (prior live) / CURRENT NOT RUN | WH-M3-003 includes keyboard focus evidence; repeat across current packaged screens. |
| U-02 | VoiceOver names, values, selected states, and announcements | AUTOMATED PASS / LIVE NOT RUN | Five Accessibility UI tests and system audits passed previously; listen through current packaged flows. |
| U-03 | No meaning conveyed only by color | AUTOMATED PASS / LIVE NOT RUN | Accessibility audits and screenshot review passed; recheck current package. |
| U-04 | Long Russian and English content | AUTOMATED PASS / LIVE NOT RUN | Long-content UI fixtures passed; inspect current packaged History and Modes. |
| U-05 | Missing permissions leave unaffected screens usable | AUTOMATED PASS / LIVE NOT RUN | Onboarding, Home, Settings, and Recordings fixtures pass; revoke permissions for the current package and navigate unaffected screens. |
| U-06 | Dictation and recording HUDs do not steal target focus | PASS (prior live) / CURRENT NOT RUN | Prior mode-switcher/focus and overlay evidence passed; repeat with current package in each target app. |
| U-07 | Modes-list circle activates directly and menu stays task-focused | AUTOMATED PASS / LIVE NOT RUN | The leading 44-point button activates without changing row selection, exposes `Activate <mode>` plus Active/Inactive, and the ellipsis no longer contains Activate; row inspection and the detail-panel `Activate Mode` action remain. The built-in-display UI run exercised activation, selection, detail action, and menu contents successfully; VoiceOver confirmation is batched for owner testing. |
| U-08 | Repeated Change Mode shortcut advances selection | AUTOMATED PASS / LIVE NOT RUN | Controller coverage proves the first global shortcut presents once on the active mode and repeats advance through all three modes with wrap without rebuilding the panel. The built-in-display UI run exercised keyboard navigation, activation, Escape, and footer guidance successfully; physical packaged shortcut confirmation is batched for owner testing. |

## Distribution matrix

| ID | Case | Result | Evidence and remaining live check |
|---|---|---|---|
| X-01 | Clean supported-Mac build | PASS | Full `scripts/verify.sh` passed all twelve stages again on 2026-09-30: 322 unit/service tests and 17 UI tests completed with zero failures before `build/Whisper.app` was rebuilt and signed. |
| X-02 | Signature and bundle identity | PASS | `codesign --verify --deep --strict` passes; identifier is `dev.yury.whisper`; executable is arm64-only. |
| X-03 | Gatekeeper recognizes the ad-hoc build as unnotarized | PASS | `spctl --assess --type execute build/Whisper.app` returned expected exit 3 and `rejected`. |
| X-04 | Move exact bundle to `/Applications` | PASS (current package smoke) | On 2026-09-29 the exact verified `build/Whisper.app` was copied to `/Applications/Whisper.app`, its strict signature and `dev.yury.whisper` identity were rechecked, and the executable launched from the installed path. The prior installed app was restored afterward. |
| X-05 | First launch through right-click Open | PASS (prior package) / CURRENT NOT RUN | Finder's contextual Open launched the 2026-09-15 quarantined bundle through App Translocation. Gatekeeper windows were routed by macOS to the external display and dismissed without interaction. Repeat with the 2026-09-16 package. |
| X-06 | Onboarding links open exact permission panes | PASS (prior live) / CURRENT NOT RUN | WH-M3-001 verified the routes and recovery states; repeat from the packaged build. |
| X-07 | API key survives relaunch in Keychain and never appears in logs | AUTOMATED PASS / LIVE BLOCKED | Twelve Keychain lifecycle, cache, query, and legacy-interaction tests pass; Settings startup/refresh now checks item presence without retrieving the secret. A no-cursor launch of the current ad-hoc package against the mismatched older item remained alive in its event loop, showed zero SecurityAgent windows, and had no `SecItemCopyMatching` frame in the sanitized process sample. The key was not read, printed, changed, or logged. A live authorized read after relaunch remains required to prove the full row. |
| X-08 | History and modes survive rebuilt and relocated launches | PASS (current package smoke) | On 2026-09-29 the owner store was quarantined without reading its contents, then one fixed synthetic custom-mode ID and one fixed synthetic dictation ID were written into a compatible legacy store through the production repositories. Launching the verified package migrated both IDs into the canonical store. They survived a clean repackage and relaunch from `build/Whisper.app`, then a copy plus exact executable launch from `/Applications/Whisper.app`. The canonical metadata directory remained `0700`, and recordings continued to resolve under `Application Support/Whisper/Recordings`. The original canonical and legacy store families plus the prior installed app were restored afterward; disposable synthetic artifacts were moved to Trash. The complete gate passed 322 unit/service tests, 17 UI tests, Release packaging, and strict signature verification. Previously missing records remain unrecoverable from the accessible legacy store because it already contains zero history records. |
| X-09 | Stable local signature and permission continuity | PASS | On 2026-09-30, after a Mac reboot, two independent clean Release builds had the same `Whisper Local Development` authority, certificate SHA-1 `3918F34830AA1C4307777059BC515CCB72620601`, `dev.yury.whisper` identifier, CDHash, and certificate-bound designated requirement. The exact rebuilt package launched without another Keychain prompt, and read-only System Settings inspection confirmed that Microphone, Accessibility, Input Monitoring, and Screen & System Audio Recording all remained enabled after the reboot and both rebuilds. The subsequent full 322-unit/17-UI verification gate and strict signature check passed. No permission switch or TCC database was changed during the check. |

## Blocking release session

Failed criterion: `WH-M6-003` requires every manual row to pass on the current packaged version or produce a resolved, verified follow-up. `X-08`, `X-09`, and the Warp/TextEdit insertion boundary now have current package or production-service smoke evidence; `D-14`, `U-07`, and `U-08` still require their physical packaged repetitions under `WH-M6-003`. Rows marked `NOT RUN`, `LIVE NOT RUN`, or `LIVE BLOCKED` still cannot be promoted using automated evidence alone.

Reason: stable metadata migration, stable-signature permission continuity, and the Warp-specific insertion path now have complete automated and focused live evidence. Physical Push-to-Talk, mode behavior, audio, permission-revocation recovery, Gatekeeper, and authorized Keychain-relaunch checks remain consolidated under final acceptance.

Affected tasks: `WH-M6-003`, `WH-M6-005`, and `WH-M6-006`.

Recommended default: deliver the verified review commits under the required GitHub identity, then reserve one foreground acceptance session when macOS authorization dialogs may be handled on whichever display receives them. Use only generated text/audio, repair access through the explicit Replace/Save action in Settings if the older Keychain item requires authorization, run the remaining live rows, and record only outcomes and sanitized notes here.

Required external change: the external display becomes available briefly for Gatekeeper, Keychain, and macOS permission confirmations, or it is physically disconnected before the session so macOS must place those dialogs on the built-in display. No credential needs to be disclosed or recorded.
