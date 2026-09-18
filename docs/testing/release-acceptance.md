# Whisper MVP release acceptance

Overall result: **BLOCKED — foreground acceptance found scoped release defects WH-M6-008 through WH-M6-011; remaining macOS-dialog checks are also pending**

Date: 2026-09-18

Environment: Apple Silicon MacBook Pro; macOS 26.4.1; Xcode 26.6 (17F113); Swift 6.3.3; macOS SDK 26.5; XcodeGen 2.46.0.

Build under test: runtime commit `bccbe65` with docs-only source follow-up `e9ea1ca`; ad-hoc `build/Whisper.app`; bundle identifier `dev.yury.whisper`; arm64.

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
| D-14 | Warp insertion after translated dictation | FAIL | The generated dictation was recorded and transformed, and History identified target bundle `dev.warp.Warp-Stable`, but the focused Warp input remained unchanged while the HUD reported `Inserted`. Warp accepts the selected-text Accessibility write without applying it; `WH-M6-008` routes this bundle through verified paste fallback. No dictated content is retained in evidence. |

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
| U-07 | Modes-list circle activates directly and menu stays task-focused | FAIL / DESIGN APPROVED | The leading circle currently selects the row while activation is hidden in the ellipsis menu. `WH-M6-011` makes the circle a labeled activation control, removes menu Activate, and keeps the detail-panel action. |
| U-08 | Repeated Change Mode shortcut advances selection | FAIL / DESIGN APPROVED | Control-Command-M currently opens/rebuilds the switcher but does not cycle its selection. `WH-M6-011` adds repeat-to-next with wrap while retaining arrows, Return, Escape, filtering, and focus restoration. |

## Distribution matrix

| ID | Case | Result | Evidence and remaining live check |
|---|---|---|---|
| X-01 | Clean supported-Mac build | PASS | Full `scripts/verify.sh` passed all twelve stages on 2026-09-16: 301 unit/service tests and 15 UI tests completed with zero failures before `build/Whisper.app` was rebuilt and signed. UI-test windows were explicitly placed on the built-in display. |
| X-02 | Signature and bundle identity | PASS | `codesign --verify --deep --strict` passes; identifier is `dev.yury.whisper`; executable is arm64-only. |
| X-03 | Gatekeeper recognizes the ad-hoc build as unnotarized | PASS | `spctl --assess --type execute build/Whisper.app` returned expected exit 3 and `rejected`. |
| X-04 | Move exact bundle to `/Applications` | PASS (prior package) / CURRENT NOT RUN | The 2026-09-15 verified package was copied without replacement and rechecked at the destination. The 2026-09-16 Keychain-recovery package has only been launched from `build/Whisper.app` and still needs the installation step repeated. |
| X-05 | First launch through right-click Open | PASS (prior package) / CURRENT NOT RUN | Finder's contextual Open launched the 2026-09-15 quarantined bundle through App Translocation. Gatekeeper windows were routed by macOS to the external display and dismissed without interaction. Repeat with the 2026-09-16 package. |
| X-06 | Onboarding links open exact permission panes | PASS (prior live) / CURRENT NOT RUN | WH-M3-001 verified the routes and recovery states; repeat from the packaged build. |
| X-07 | API key survives relaunch in Keychain and never appears in logs | AUTOMATED PASS / LIVE BLOCKED | Twelve Keychain lifecycle, cache, query, and legacy-interaction tests pass; Settings startup/refresh now checks item presence without retrieving the secret. A no-cursor launch of the current ad-hoc package against the mismatched older item remained alive in its event loop, showed zero SecurityAgent windows, and had no `SecItemCopyMatching` frame in the sanitized process sample. The key was not read, printed, changed, or logged. A live authorized read after relaunch remains required to prove the full row. |
| X-08 | History and modes survive rebuilt and relocated launches | AUTOMATED PASS / LIVE NOT RUN | Synthetic migration tests preserve IDs for modes, dictations, meetings, transcript segments, and cleanup tombstones at `Application Support/Whisper/Metadata/Whisper.store`; canonical-wins, idempotence, unrelated-store, copy-failure, permissions, and explicit reopen cases pass. The final rebuilt/relocated package smoke is intentionally batched for owner testing after all release-follow-up code is complete. Previously missing records are not recoverable from the accessible legacy store because it already contains zero history records. |

## Blocking release session

Failed criterion: `WH-M6-003` requires every manual row to pass on the current packaged version or produce a resolved, verified follow-up. Rows `D-14`, `U-07`, `U-08`, and `X-08` now map to `WH-M6-008` through `WH-M6-011`. Rows marked `NOT RUN`, `LIVE NOT RUN`, or `LIVE BLOCKED` still cannot be promoted using automated evidence alone.

Reason: foreground QA found a false-positive Warp insertion path, unstable implicit SwiftData storage, missing built-in presets, and non-obvious mode activation/cycling behavior. The approved fixes are sequenced as `WH-M6-008`, `WH-M6-009`, `WH-M6-010`, and `WH-M6-011`; acceptance resumes after they pass. Separately, the remaining audio, permission, recovery, Gatekeeper, and authorized Keychain-relaunch checks may open macOS dialogs on the unavailable external display and cannot proceed safely under the current display constraint.

Affected tasks: `WH-M6-003`, `WH-M6-005`, `WH-M6-006`, and release follow-ups `WH-M6-008` through `WH-M6-011`.

Recommended default: implement and verify `WH-M6-008` through `WH-M6-011` in dependency order, then reserve one foreground acceptance session when macOS authorization dialogs may be handled on whichever display receives them. Use only generated text/audio, repair access through the explicit Replace/Save action in Settings if the older Keychain item requires authorization, run D-01 through X-08, and record only outcomes and sanitized notes here.

Required external change: the external display becomes available briefly for Gatekeeper, Keychain, and macOS permission confirmations, or it is physically disconnected before the session so macOS must place those dialogs on the built-in display. No credential needs to be disclosed or recorded.
