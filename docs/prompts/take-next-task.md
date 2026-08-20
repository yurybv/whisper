# Prompt: Take the next task

Act as the senior implementation owner for Whisper.

1. Read `AGENTS.md`, the workflow, backlog, roadmap, approved spec, and test strategy.
2. Run the repository/account guard. Stop before push if the account is not `yurybv` or the remote is not the approved HTTPS URL.
3. Run the project-state script, fetch `origin/master`, and reconcile dirty files, unpublished commits, and backlog/detail status mismatches.
4. Resume an `in-progress` task or finish a `review` task. Only when neither exists, select the lowest-numbered `ready` task in the earliest open milestone whose dependencies are done.
5. Read its full milestone record and linked implementation-plan section.
6. State task ID/title, scope, expected files, required tests, dependencies, and blockers.
7. If safe, change only a newly selected task to `in-progress` and implement it with TDD.
8. Run focused and milestone checks, review the diff, and perform required manual QA.
9. Set the task to `done` only after verification passes; update dependent task statuses and backlog.
10. Commit with a Conventional Commit message and push directly to `master` after rerunning the account guard.

Ask the owner only for blockers listed in `AGENTS.md`. Do not create a GitHub Issue or PR.

Final report:

- task completed;
- commit and push result;
- files changed;
- tests and manual checks;
- acceptance criteria evidence;
- anything incomplete;
- next ready task.
