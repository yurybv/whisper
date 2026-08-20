# ADR 0003: Separate metadata and audio storage

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

Whisper stores queryable modes, dictation history, meeting jobs, and transcript segments while also producing audio files that can be large and must survive failed network processing. Preferences and the OpenAI API key have different lifecycle and security requirements from both metadata and audio.

## Decision

Use SwiftData for structured metadata and relationships. Store recording audio and retry chunks as files below `Library/Application Support/Whisper`, referenced from SwiftData by validated relative paths. Write active meeting tracks continuously to their meeting directory rather than retaining complete recordings in memory.

Use UserDefaults only for lightweight preferences and macOS Keychain only for the OpenAI API key. Chunk files are disposable after their transcript is persisted; source tracks remain until retention or confirmed deletion removes them.

Confirmed meeting deletion creates a SwiftData cleanup tombstone containing the validated relative meeting-directory path in the same transaction that removes the history record. The file service removes that directory and then deletes the tombstone. Startup recovery retries any surviving tombstone, so filesystem failure never leaves private audio without a durable cleanup owner.

## Consequences

- History and recovery queries use native typed persistence without placing large blobs in the database.
- Source audio survives relaunch and transient processing failures.
- Database and file changes require coordinated cleanup and recovery rules.
- Deletion tombstones add a small persistence type but make cross-store cleanup retryable.
- Relative paths must never escape the Whisper Application Support root.
- Backups and manual removal need to account for both the metadata store and Application Support files.

## Rejected alternatives

- Audio blobs in SwiftData: rejected because long recordings would inflate the metadata store and complicate streaming writes and cleanup.
- JSON files for all metadata: rejected because relationships, migrations, queries, and transactional updates would need custom infrastructure.
- UserDefaults for history: rejected because it is intended for preferences, not durable relational records.
- Temporary-directory-only audio: rejected because the operating system may purge it and failed jobs must remain resumable.

## References

- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [FileManager application support directory](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/applicationsupportdirectory)
- [Approved storage layout](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#storage-layout)
