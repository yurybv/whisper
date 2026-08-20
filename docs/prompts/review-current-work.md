# Prompt: Review current work

Review the current working tree against its single `in-progress` task.

Check:

- diff stays inside task scope;
- acceptance criteria are implemented and observable;
- required tests exist and test behavior rather than implementation details;
- Swift concurrency and macOS lifecycle handling are safe;
- audio and metadata paths cannot escape Application Support/Whisper;
- API key, Authorization, dictated text, transcript, and instructions are not logged;
- UI changes preserve keyboard focus, VoiceOver labels, non-color status, and the approved design;
- docs and task statuses match reality;
- `git diff --check` and required commands pass.

Return `APPROVE` or `REQUEST CHANGES`. For every requested change, include severity, file/line, evidence, impact, and the smallest safe fix. Do not commit during a review-only run.
