# Prompt: Take the next tasks loop

Process up to three safe Whisper tasks sequentially. Never implement tasks in parallel.

For each iteration:

1. Follow `docs/prompts/take-next-task.md` to select exactly one ready task.
2. Implement, test, review, commit, and push that task completely.
3. Confirm the commit exists on `origin/master` before selecting another task.
4. If the next action is a milestone review, run that review as the next task.

Stop when:

- three tasks are complete;
- no ready task exists;
- an owner decision, permission dialog, credential, paid service, or unsupported platform behavior blocks progress;
- tests fail and repository evidence does not support a safe fix;
- product/spec/task sources conflict;
- the account or remote guard fails.

Do not create GitHub Issues, branches, PRs, or force pushes.

Final report:

1. tasks completed;
2. commits pushed;
3. tasks inspected but not started;
4. blockers;
5. owner decisions needed;
6. tests and manual QA;
7. next recommended task.
