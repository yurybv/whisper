# Whisper Autonomous Prompt Pack

These prompts operate on local task records. GitHub Issues are intentionally not used.

The preferred Codex entry point is the repository-local `$whisper-next-task` skill. It restores interrupted work before applying the prompts below.

- `take-next-task.md`: select the next safe ready task.
- `take-next-tasks-loop.md`: complete up to three tasks sequentially.
- `implement-task.md`: implement one explicit ready task.
- `review-current-work.md`: review the current diff against its task.
- `milestone-review.md`: close a milestone and unlock the next.
- `audit-drift.md`: detect product, architecture, privacy, test, and backlog drift.

Every prompt must follow `AGENTS.md`. Before push, the account must be `yurybv` and the remote must be `https://github.com/yurybv/whisper.git`.
