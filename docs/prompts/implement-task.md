# Prompt: Implement one task

Implement exactly task `<TASK_ID>`.

Required procedure:

1. Read `AGENTS.md` and all documents linked by the task.
2. Verify the task is `ready`, its dependencies are `done`, and no previous milestone review is open.
3. Run the account/remote guard and inspect the working tree.
4. List expected files and required checks before editing.
5. Set the task to `in-progress`.
6. Use TDD: failing focused test, minimal implementation, passing focused test.
7. Run every required task and milestone check.
8. Review for scope, privacy, concurrency, lifecycle, accessibility, and test quality.
9. Complete applicable manual QA.
10. Set the task to `done`, update backlog/dependencies, commit, recheck account/remote, and push to `master`.

Do not implement neighboring tasks, create GitHub Issues, or open a PR.
