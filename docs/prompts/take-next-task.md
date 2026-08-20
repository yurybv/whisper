# Prompt: Take the next task

Act as the senior implementation owner for Whisper.

1. Read `AGENTS.md`, the workflow, backlog, roadmap, approved spec, and test strategy.
2. Run the repository/account guard. Stop before push if the account is not `yurybv` or the remote is not the approved HTTPS URL.
3. Select the lowest-numbered `ready` task in the earliest open milestone whose dependencies are done.
4. Read its full milestone record and linked implementation-plan section.
5. State task ID/title, scope, expected files, required tests, dependencies, and blockers.
6. If safe, change only that task to `in-progress` and implement it with TDD.
7. Run focused and milestone checks, review the diff, and perform required manual QA.
8. Set the task to `done` only after verification passes; update dependent task statuses and backlog.
9. Commit with a Conventional Commit message and push directly to `master` after rerunning the account guard.

Ask the owner only for blockers listed in `AGENTS.md`. Do not create a GitHub Issue or PR.

Final report:

- task completed;
- commit and push result;
- files changed;
- tests and manual checks;
- acceptance criteria evidence;
- anything incomplete;
- next ready task.
