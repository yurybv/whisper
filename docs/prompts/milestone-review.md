# Prompt: Review a milestone

Run the explicit milestone review task for milestone `<MILESTONE>`.

1. Read all tasks and commits in the milestone.
2. Verify every non-review task is done on `origin/master`.
3. Run the milestone's complete automated and manual checks.
4. Audit product scope, architecture, privacy/logging, accessibility, test quality, and recovery behavior.
5. Identify missing scope, stale future tasks, and blockers.
6. Write `docs/implementation/reviews/<milestone>-review.md` with evidence and an `APPROVE NEXT MILESTONE` or `BLOCKED` verdict.
7. If approved, set the review task to done and unblock only the first task(s) whose dependencies are satisfied.
8. Commit and push after the account/remote guard.

Do not add feature code or skip evidence to make the milestone appear complete.
