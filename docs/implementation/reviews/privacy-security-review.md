# Privacy, security, and logging review

- **Task:** WH-M6-004
- **Date:** 2026-09-15
- **Scope:** Keychain use, local storage permissions, path containment, runtime logging and error payloads, Authorization handling, audio lifecycle and deletion, dependencies, and outbound network boundaries.
- **Result:** PASS after fixing PSR-001 and PSR-002. No open release blocker was found in this scope.

## Executive summary

Whisper keeps the OpenAI API key in macOS Keychain, adds it only to outbound requests at execution time, and has no runtime logging calls. The app sends audio, dictated text, and mode instructions only to the configured OpenAI API over HTTPS; it has no third-party packages, analytics, cloud sync, or additional runtime network client. Recording paths are UUID-derived, resolved against the owned recordings root, and validated again before reads or scoped deletion. Confirmed meeting deletion is backed by a durable cleanup tombstone.

The review found two implementation defects. Provider-controlled API error bodies could survive inside an error value and become visible through debug/reflection formatting. Existing app-owned audio directories also inherited permissive `0755` modes and the configured root could be a symbolic link. Both findings are fixed and covered by regression tests: response bodies are discarded on HTTP failure, and app-owned audio directories are verified as real directories and normalized to `0700`.

The security-best-practices skill has no Swift/macOS-specific reference document. This review therefore applies the approved Whisper privacy specification, repository architecture decisions, Apple platform primitives already selected by the project, and direct code/test evidence rather than claiming coverage against a separate framework checklist.

## High severity

No open high-severity findings.

### PSR-001 — Resolved — Provider error payload retained private content

- **Impact:** A provider-controlled error message that echoed an API key, Authorization value, dictated text, transcript, or instruction could be exposed by diagnostic or reflective error formatting.
- **Evidence before fix:** HTTP error bodies were decoded into the associated value of `OpenAIClientError.api` or `transientAPI`.
- **Resolution:** `OpenAIClient.execute` now classifies failures by status and discards the response body before creating a payload-free error (`Sources/OpenAI/OpenAIClient.swift:193-201`). The public descriptions are fixed generic strings (`Sources/OpenAI/OpenAIModels.swift:51-58`).
- **Regression coverage:** `RedactionTests` injects a fake provider response containing credential-, Authorization-, dictation-, and instruction-shaped values and asserts that localized, describing, reflecting, and user-presented forms omit every value (`Tests/WhisperTests/Security/RedactionTests.swift:5-46`). `OpenAIClientTests` separately verifies that a 400 response message is discarded.

## Medium severity

No open medium-severity findings.

### PSR-002 — Resolved — App-owned audio directories used inherited permissions

- **Impact:** On a Mac with an unusually permissive parent directory, inherited `0755` permissions could expose directory names and audio paths to other local users; accepting a symbolic-link root could redirect writes outside the intended storage boundary.
- **Resolution:** Every app-owned root, `Recordings`, `Temporary`, and per-meeting directory is now verified as a non-symbolic-link directory and normalized to owner-only `0700` (`Sources/Persistence/AppPaths.swift:8-49`, `Sources/Persistence/AppPaths.swift:116-135`). The meeting recorder uses this hardened creation path (`Sources/Audio/ScreenCaptureMeetingRecorder.swift:124-134`).
- **Regression coverage:** Persistence tests assert `0700` on all four directory levels and reject a symbolic-link application-support root (`Tests/WhisperTests/Persistence/PersistenceTests.swift:62-98`). Existing traversal, cross-meeting, symbolic-link redirection, scoped-deletion, and cleanup-retry tests remain in the full suite.

## Reviewed controls

### Secrets and Authorization

- The production key store is a generic-password Keychain item and new items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`Sources/Core/KeychainSecureStore.swift:19-73`).
- Runtime wiring wraps Keychain with the approved process-memory cache; it does not persist the key in UserDefaults or SwiftData (`Sources/WhisperApp/AppRuntime.swift:133`).
- The Authorization header is created immediately before `URLSession` execution (`Sources/OpenAI/OpenAIClient.swift:168-177`). No request, header, key, body, transcript, or instruction is logged.
- The canonical privacy scan rejects logging APIs in production Swift sources and live OpenAI credential patterns outside tests and documentation (`scripts/verify.sh:55-69`).

### Local storage, containment, and deletion

- Durable audio and retry chunks live below `Library/Application Support/Whisper`; only validated relative recording paths are persisted. Resolution rejects absolute paths, traversal, paths outside `Recordings`, wrong meeting IDs, and symbolic-link escapes (`Sources/Persistence/AppPaths.swift:41-113`).
- SwiftData metadata intentionally uses the platform-managed metadata store while large audio remains in Application Support, as recorded in ADR 0003. This is an approved two-store design, not an unowned audio path (`docs/architecture/adr/0003-separate-metadata-and-audio-storage.md:11-26`).
- Successful dictation removes temporary audio; recoverable processing failure retains it for Retry or Discard (`Sources/Dictation/DictationCoordinator.swift:323-371`). Disposable meeting chunks are removed only after their transcript result is persisted, while durable source tracks remain until confirmed deletion (`Sources/Meetings/MeetingTranscriber.swift:239-243`).
- Meeting deletion saves metadata removal and a UUID-bound cleanup tombstone before attempting filesystem removal. Failed cleanup stays durable and is retried; only the exact `meeting-<UUID>` directory is eligible (`Sources/Persistence/HistoryRepository.swift:207-243`). The `Forever` policy performs no unsolicited deletion.

### Network and dependencies

- Production REST traffic is implemented by the single `OpenAIClient` URLSession boundary. Its default base is `https://api.openai.com/v1`; endpoints are limited to `audio/transcriptions`, `responses`, and the configured transcription model under `models` (`Sources/OpenAI/OpenAIConfiguration.swift:3-21`, `Sources/OpenAI/OpenAIClient.swift:58-132`).
- Transformation requests set `store: false` (`Sources/OpenAI/OpenAIClient.swift:88-103`). Audio, text, and instruction content are transmitted because they are required for the user-requested OpenAI operation; automated tests replace URLSession and do not contact OpenAI.
- The only other external URL in production sources is the user-initiated `https://platform.openai.com/api-keys` onboarding link. There are no package dependencies and no analytics, telemetry, advertising, update, or cloud-sync client.
- The application entitlement file is empty. The approved personal MVP is ad-hoc signed and not sandboxed; notarization, Developer ID, and formal penetration/compliance review remain explicitly out of scope.

## Verification

The review used source/dependency/network scans plus focused Keychain, redaction, OpenAI, persistence, retention, recorder, lifecycle, and deletion tests. The canonical noninteractive verification command then regenerated the project, compiled both test targets, ran the complete unit/service suite, packaged the Release application, and verified its ad-hoc signature. UI execution was intentionally skipped under the owner's no-focus/no-cursor-interference instruction; `WH-M6-003` separately tracks the required foreground release session.

Detailed commands and results are recorded in `docs/testing/evidence/WH-M6-004/qa.md`.
