# ADR 0005: Capture meetings with ScreenCaptureKit

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

A meeting record must contain both the local speaker and remote participants, preserve the two sources for You/Others attribution, survive up to three hours, and avoid capturing Whisper's own sound effects. The app does not need screen video.

## Decision

Use one ScreenCaptureKit stream configured for system audio and microphone capture. Consume the `.audio` and `.microphone` outputs separately and write each source continuously to its own AAC M4A file through independent serial writer queues. Set `excludesCurrentProcessAudio` so app feedback is not captured.

The capture service exposes a protocol boundary to the meeting coordinator. It returns a captured meeting only after both writers finalize, enforces disk and duration limits, and never buffers an entire meeting in memory. If one track fails, it finalizes the surviving writer and returns a structured partial-capture error containing the missing source and every finalized file path. The coordinator persists that result as failed or interrupted before control returns to the UI; `captured` is reserved for two finalized tracks.

## Consequences

- Separate tracks provide deterministic You/Others attribution without remote-speaker identity claims.
- Screen Recording and Microphone permissions are both required for complete capture.
- Stream callbacks, writer finalization, device loss, and permission revocation require explicit lifecycle handling.
- A partial-track failure remains a durable history job with the usable source path, rather than an untracked file.
- macOS 15 is the minimum because ScreenCaptureKit microphone capture and the microphone output type are available there.
- Capture adapters require fakes for automated tests; real system-audio verification remains manual.

## Rejected alternatives

- AVAudioEngine for both sources: rejected because it records microphone devices but does not provide the approved system-audio capture path.
- One mixed audio file: rejected because it loses reliable source labeling and independent failure recovery.
- A virtual loopback driver: rejected because installing and maintaining a separate audio driver expands scope and support risk.
- Screen video capture: rejected because the product needs audio only and video would increase privacy, storage, and processing cost.

## References

- [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [SCStreamConfiguration captureMicrophone](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone)
- [SCStreamOutputType microphone](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype/microphone)
- [Approved call recording behavior](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#call-recording-behavior)
