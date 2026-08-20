# Whisper Agent Workflow

This repository is developed primarily by agentic workers for a personal macOS MVP. The owner should only be asked for input when a product decision cannot be derived safely from the approved specification.

## Source of truth

Active work is defined only by local task records under `docs/implementation/tasks/`.

Before selecting or implementing a task, read:

- `docs/implementation/task-workflow.md`
- `docs/implementation/task-backlog.md`
- `docs/implementation/roadmap.md`
- `docs/superpowers/specs/2026-08-19-whisper-macos-mvp-design.md`
- the selected milestone task file
- the linked section of `docs/superpowers/plans/2026-08-19-whisper-macos-mvp.md`
- `docs/testing/test-strategy.md` when code is involved

Do not create or use GitHub Issues as task records. Do not invent product behavior that conflicts with the approved specification or Open Design prototype.

## Repository and account guard

Before every push, run:

```bash
gh api user --jq .login
git remote get-url origin
git branch --show-current
git status --short
```

Required values:

- GitHub account: `yurybv`
- remote: `https://github.com/yurybv/whisper.git`
- delivery branch: `master`

If the account or remote differs, stop before pushing. Never push this repository through a Wecasa account or SSH identity.

## Task workflow

- Select one `status: ready` task whose dependencies are done.
- Change it to `status: in-progress` before implementation.
- Keep the change inside that task's scope.
- Follow TDD for feature and bug tasks.
- Run every required automated check plus relevant manual QA.
- Review the diff and update documentation before completion.
- Change the task to `status: done` only after verification passes.
- Use one focused commit per task, or a small commit series when the task explicitly requires it.
- Push directly to `master` after the account guard and verification pass.
- Do not create PRs unless the owner explicitly requests one.

## Autonomy rules

Agents may make implementation-level choices that preserve the approved behavior, architecture, privacy boundaries, and UI direction. Prefer the smallest reliable solution.

Ask the owner only when:

- a change would expand product scope;
- a macOS permission or platform limitation invalidates approved behavior;
- a new recurring cost or paid service is required;
- secrets, certificates, notarization, or App Store credentials are needed;
- two safe alternatives have materially different user-visible behavior;
- required verification cannot be completed with the available Mac and tools.

Do not ask for routine naming, file placement, refactoring, test structure, or library decisions when repository evidence supports a safe choice.

## Completion rules

Do not claim a task is complete unless:

- acceptance criteria are satisfied;
- required tests pass;
- manual QA is complete or explicitly documented as not applicable;
- no secret, dictated text, transcript, instruction, or Authorization header is logged;
- related task, roadmap, and README documentation is current;
- `git diff --check` passes;
- the final commit is present on `origin/master`.

Every milestone ends with its milestone review task. Do not start the next milestone until that review is done.
