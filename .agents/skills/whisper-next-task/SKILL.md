---
name: whisper-next-task
description: Use when working in the Whisper repository and the user asks to continue or resume development, determine what was completed, take the next task, or work through the local backlog.
---

# Whisper Next Task

Recover the repository's real state before selecting work. Continue unfinished work before taking a new task; the versioned task records remain the source of truth.

## Workflow

1. Confirm the repository root and read `AGENTS.md`. Then read the workflow, backlog, roadmap, approved specification, implementation plan, and test strategy named there.
2. Run `bash .agents/skills/whisper-next-task/scripts/project-state.sh`. If the approved GitHub account, remote, or branch guard fails, do not push.
3. Fetch `origin/master`, rerun the state report, and inspect any local commits not on the remote.
4. Reconcile evidence in this order:
   - Preserve a dirty worktree. Inspect its diff and map it to a task before changing anything.
   - Resolve disagreement between the backlog and detailed task records before implementation.
   - Resume an `in-progress` task.
   - Finish verification for a `review` task.
   - Review unpublished local commits before selecting new work.
   - Only when no work is active, select the lowest-numbered eligible `ready` task in the earliest open milestone.
5. Read the selected task's complete record and linked sources. Report its ID, scope, expected files, checks, dependencies, and blockers in a concise progress update.
6. Mark a new task `in-progress` in both its detailed record and backlog. Do not relabel an existing task without evidence from its diff, commits, and acceptance criteria.
7. Implement exactly one task. Follow TDD for feature, bug, and behavior changes. Run the task checks, relevant milestone checks, manual QA, and `git diff --check`.
8. Move the task through `review` to `done` only after its acceptance criteria pass. Update newly unblocked tasks, roadmap, and review records in the same coherent change.
9. Commit with Conventional Commits. Rerun the account guard, push directly to `master`, and verify the commit exists on `origin/master`. Never create GitHub Issues or a PR unless the owner explicitly asks.

If existing changes cannot be mapped safely, statuses conflict with implementation evidence, or an `AGENTS.md` blocker applies, preserve all work and ask only for the minimum required decision.

## Completion Report

Return the recovered starting state, task completed, commit and push result, changed files, tests and manual checks, incomplete items, and next eligible task.

For a user-requested multi-task run, complete at most three tasks sequentially and verify each on `origin/master` before selecting the next.
