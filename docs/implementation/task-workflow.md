# Local Task Workflow

This repository intentionally uses versioned Markdown task records instead of GitHub Issues.

## Task lifecycle

Valid statuses:

- `blocked`: a named dependency or owner decision prevents implementation;
- `ready`: scoped, testable, and safe to start;
- `in-progress`: selected by one worker;
- `review`: implementation is complete and verification/review is running;
- `done`: verified commit is on `origin/master`.

Only one implementation task may be `in-progress` at a time. Milestone review tasks may inspect already completed work but must not add unrelated feature code.

## Definition of ready

A task is ready only when it has:

- an ID, title, milestone, status, priority, and type;
- clear scope and out-of-scope boundaries;
- observable acceptance criteria;
- exact required tests or commands;
- dependencies and blockers;
- expected affected files;
- a linked specification or implementation-plan section;
- no unresolved dependency on a later milestone.

## Selecting the next task

1. Run the repository and account guard from `AGENTS.md`.
2. Run `.agents/skills/whisper-next-task/scripts/project-state.sh` and fetch `origin/master` when the guard passes.
3. Inspect and preserve dirty files, unpublished commits, and status mismatches.
4. Resume an `in-progress` task or finish a `review` task before selecting new work.
5. If no work is active, read `docs/implementation/task-backlog.md` and find the earliest milestone that has a `ready` task.
6. Select the lowest-numbered ready task whose dependencies are done.
7. Read its full task record and linked plan section.
8. Change only that task to `status: in-progress` and commit that status with the implementation or as the first commit of the task series.

Do not skip a milestone review gate. Do not select a blocked task simply because it is interesting.

## Implementation cycle

For each task:

1. List expected files and required checks.
2. Write a failing test for the next behavior.
3. Run the focused test and confirm the expected failure.
4. Implement the smallest passing change.
5. Run the focused test, then the milestone-level checks.
6. Inspect the diff for scope, privacy, concurrency, and macOS lifecycle mistakes.
7. Perform the task's manual QA when required.
8. Set `status: review`, run final verification, then set `status: done`.
9. Commit with Conventional Commits and push only after the account guard passes.

## Commit and push rules

- Delivery branch: `master`.
- One task equals one focused commit or a small coherent series.
- Do not create a PR unless explicitly requested.
- Never force-push.
- Do not rewrite commits already on `origin/master`.
- Preserve unrelated user changes.
- Before push, verify `gh api user --jq .login` returns `yurybv` and the remote is HTTPS under `yurybv/whisper`.

## Definition of done

A task is done only when:

- acceptance criteria are satisfied;
- required tests and commands pass;
- manual QA is complete or a concrete reason says why it is not applicable;
- docs and task statuses match the implementation;
- no secrets or private content appear in code, fixtures, logs, screenshots, or commits;
- `git diff --check` passes;
- the task commit exists on `origin/master`.

## Blockers

Create a blocker section in the task record and stop when:

- Apple APIs cannot support the approved behavior;
- a certificate, paid service, secret, or owner credential is required;
- user-visible behavior has two materially different safe interpretations;
- the selected Mac cannot run a required acceptance test;
- required verification fails and repository evidence does not support a safe correction.

The blocker must name the failed criterion, evidence, affected tasks, recommended default, and exact owner decision or external change required.

## Milestone review

Each milestone review checks:

- completed and missing scope;
- architecture and product drift;
- test quality and manual QA evidence;
- privacy and logging rules;
- open blockers and stale future tasks;
- whether the next milestone is safe to start.

The review updates the backlog and roadmap in the same commit. It does not silently expand product scope.
