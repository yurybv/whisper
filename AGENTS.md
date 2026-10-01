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

When the owner asks to continue development, resume previous work, or take the next task, use the repository-local `whisper-next-task` skill under `.agents/skills/`. It must recover dirty work, unpublished commits, and active task statuses before selecting a new `ready` task.

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

- Recover and reconcile any dirty worktree, unpublished commit, `in-progress` task, or `review` task before selecting new work.
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

Every milestone ends with its milestone review task. Normally, do not start the next milestone until that review is done.

## Owner-approved update-first order (2026-10-01)

The owner explicitly prioritized versioning and in-app updates to make subsequent testing easier. This is a limited exception to numeric milestone order, not a declaration that MVP acceptance passed:

1. Complete `WH-M7-001` through `WH-M7-005`, beginning with version metadata. Their entry prerequisites are the completed verification, privacy, and stable-signing tasks (`WH-M6-002`, `WH-M6-004`, `WH-M6-013`).
2. Research the reported Right Option/start-stop problem in `WH-M6-014`, the last queued development/research item. Record evidence before proposing a fix; any confirmed defect gets a scoped follow-up.
3. Resume `WH-M6-003` after that research and any blocking fixes, then `WH-M6-005` and `WH-M6-006`. Keep unresolved acceptance rows visible throughout.

Follow the revised [update design](docs/superpowers/specs/2026-09-29-local-automatic-updates-design.md) and [plan](docs/superpowers/plans/2026-09-29-local-automatic-updates.md). The current request revises planning only; it does not itself publish a release or create a signing secret.

After the updater exists, the owner can request a release in ordinary language. The agent handles version selection, verification, packaging, signing, Git tags, GitHub Release assets, and publication on this Mac. One completed task can span several related commits and receives one patch version when requested. A source push is not publication authorization. Do not ask the owner to run build commands, prepare release notes, choose the next patch number, or repeat approval already given for that release. Ask only for a genuinely missing decision, credential, or OS-controlled consent; the owner enters authentication locally. The owner normally only invokes **Check for Updates…** and accepts installation. One initial installation at `/Applications/Whisper.app` is approved as part of the future bootstrap workflow.
