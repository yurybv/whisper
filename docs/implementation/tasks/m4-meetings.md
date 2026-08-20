# Milestone 4: Durable meeting recording

## WH-M4-001

- **Title:** Capture microphone and system audio with ScreenCaptureKit
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Capture Mac system audio and selected microphone simultaneously, write separate durable tracks continuously, expose meters/duration, and finalize safely on stop or source loss.
- **Out of scope:** Individual remote-speaker tracks, video capture, and live cloud streaming.
- **Acceptance criteria:** Both sources are represented separately; recording does not retain the full session in memory; microphone loss preserves system audio; Screen Recording revocation preserves microphone audio; cancel/delete behavior follows the spec.
- **Required checks:** Capture coordinator/file-writer tests from implementation plan Task 12; manual dual-source smoke.
- **Dependencies:** WH-M3-004.
- **Expected files:** `Sources/Audio/MeetingRecorder.swift`, ScreenCaptureKit adapters, track writers, meters, matching tests.
- **Source:** implementation plan Task 12.
- **Blockers:** Screen Recording and microphone permissions for manual QA.

## WH-M4-002

- **Title:** Export size-bounded long-audio chunks
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Plan and export overlapping audio chunks below 20 MB for each source, persist chunk progress, and support up to three hours without unbounded memory use.
- **Out of scope:** Transcript merge and processed-result generation.
- **Acceptance criteria:** Chunk files remain under the upload cap; boundaries and overlap are deterministic; progress survives relaunch; temporary exports can be rebuilt from source audio.
- **Required checks:** Chunk planning/export tests from implementation plan Task 13; synthetic three-hour size/memory test.
- **Dependencies:** WH-M4-001, WH-M2-001.
- **Expected files:** `Sources/Meetings/ChunkPlanner.swift`, `AudioChunkExporter.swift`, progress models, matching tests.
- **Source:** implementation plan Task 13.
- **Blockers:** WH-M4-001.

## WH-M4-003

- **Title:** Merge diarized chunks into a chronological transcript
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Decode diarized results, map microphone segments to You and system segments to Others, normalize timestamps, remove overlap duplicates, and produce stable chronological segments.
- **Out of scope:** Identifying remote participants by name.
- **Acceptance criteria:** You/Others labels are deterministic; overlap text is not duplicated; timestamps are monotonic; mixed Russian/English text is preserved; malformed chunk responses fail without destroying prior work.
- **Required checks:** Transcript merge, overlap, ordering, and malformed-response tests from implementation plan Task 13.
- **Dependencies:** WH-M4-002.
- **Expected files:** `Sources/Meetings/TranscriptMerger.swift`, diarization DTO mapping, matching tests.
- **Source:** implementation plan Task 13.
- **Blockers:** WH-M4-002.

## WH-M4-004

- **Title:** Implement processing, retry, and relaunch recovery
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Persist the meeting job state, upload incomplete chunks, merge transcript, apply the saved processing instructions/result language, retry transient failures, and resume on launch.
- **Out of scope:** Background processing after user logout because the MVP has no accounts; cloud sync.
- **Acceptance criteria:** Captured audio is never deleted by a processing failure; invalid key is non-retryable; no-network state exposes retry; relaunch resumes captured/transcribing/processing jobs; instruction snapshot remains stable for reprocessing.
- **Required checks:** Meeting job state-machine, retry, recovery, and processing tests from implementation plan Task 14.
- **Dependencies:** WH-M4-003, WH-M1-003, WH-M2-001.
- **Expected files:** `Sources/Meetings/MeetingProcessor.swift`, `MeetingRecoveryService.swift`, job state types, matching tests.
- **Source:** implementation plan Task 14.
- **Blockers:** WH-M4-003.

## WH-M4-005

- **Title:** Build Recordings screen and recording states
- **Type:** feature
- **Status:** blocked
- **Priority:** P0
- **Scope:** Implement the Recordings destination with Start/Stop, source status, microphone, hotkey, processing instructions, result language, elapsed time, meters, finalizing, low-disk, and permission errors.
- **Out of scope:** History details and transcript editing.
- **Acceptance criteria:** The screen matches approved composition; current capture state survives window closure; source failures are explicit; disk below 2 GB blocks start; meeting mode disables push-to-talk.
- **Required checks:** Recording view-model/UI tests; screenshot comparison; manual start/stop/cancel/low-disk states.
- **Dependencies:** WH-M4-001, WH-M4-002, WH-M4-003, WH-M4-004.
- **Expected files:** `Sources/UI/Recordings/**`, UI tests.
- **Source:** implementation plan Task 14 and approved Open Design prototype.
- **Blockers:** WH-M4-001..004.

## WH-M4-006

- **Title:** Review durable meeting recording milestone
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Audit source durability, chunk limits, transcript ordering, processing recovery, three-hour behavior, permission loss, disk handling, and UI evidence.
- **Out of scope:** Unified history implementation.
- **Acceptance criteria:** WH-M4-001..005 are done; synthetic long capture passes; relaunch recovery is proven; no source file is lost on simulated network failure; Milestone 5 is safe to start.
- **Required checks:** Full tests; synthetic long-input harness; dual-source manual QA; memory/disk observation; `git diff --check`.
- **Dependencies:** WH-M4-001 through WH-M4-005.
- **Expected files:** `docs/implementation/reviews/m4-review.md`, backlog updates.
- **Source:** roadmap Milestone 4.
- **Blockers:** Completion of meeting tasks.
