# Milestone 0: Governance and readiness

## WH-M0-001

- **Title:** Establish local task workflow and repository guardrails
- **Type:** docs
- **Status:** done
- **Priority:** P0
- **Scope:** Add the repository agent contract, roadmap, local backlog, task lifecycle, test strategy, milestone task records, and reusable autonomous-work prompts. Configure the repository to use the personal GitHub account safely.
- **Out of scope:** Application scaffolding or feature code; GitHub Issues; PR automation.
- **Acceptance criteria:** Local task files are the documented source of truth; every MVP capability maps to a task; account guard requires `yurybv`; remote uses HTTPS under `yurybv/whisper`; no task requires GitHub Issues.
- **Required checks:** `git diff --check`; task/backlog consistency script or manual ID/status/dependency audit; `gh api user --jq .login`; `git remote -v`.
- **Dependencies:** None.
- **Expected files:** `AGENTS.md`, `docs/implementation/**`, `docs/testing/test-strategy.md`, `docs/prompts/**`.
- **Source:** approved specification and implementation plan.
- **Blockers:** None.

## WH-M0-002

- **Title:** Record native architecture and tooling decisions
- **Type:** architecture
- **Status:** ready
- **Priority:** P0
- **Scope:** Add concise ADRs for XcodeGen, unsandboxed ad-hoc distribution, SwiftData plus Application Support storage, direct OpenAI REST transport, ScreenCaptureKit dual-source capture, CGEventTap shortcuts, and Accessibility insertion fallback.
- **Out of scope:** Implementing the selected architecture or adding alternative providers.
- **Acceptance criteria:** Every foundation choice has context, decision, consequences, and rejected alternatives; ADRs match the approved spec and macOS 15+ target.
- **Required checks:** `rg -n "TBD|TODO|open question" docs/architecture`; manual cross-check against the platform and technology section of the spec.
- **Dependencies:** WH-M0-001.
- **Expected files:** `docs/architecture/adr/0001-*.md` through the required decision set; `docs/architecture/system-architecture.md`.
- **Source:** `docs/superpowers/specs/2026-08-19-whisper-macos-mvp-design.md`.
- **Blockers:** None.

## WH-M0-003

- **Title:** Verify development environment and project readiness
- **Type:** chore
- **Status:** ready
- **Priority:** P0
- **Scope:** Check Xcode 26, Swift, macOS SDK, XcodeGen, Homebrew, available disk, microphone hardware, and Screen Recording capability; document exact versions and any bootstrap command.
- **Out of scope:** Installing paid tools, changing system permissions without the owner's interaction, or scaffolding the app.
- **Acceptance criteria:** A readiness report proves whether Task WH-M1-001 can run; missing free tooling has a deterministic bootstrap path; permission-dependent manual steps are explicit.
- **Required checks:** `xcodebuild -version`; `xcrun swift --version`; `xcrun --sdk macosx --show-sdk-version`; `xcodegen --version`; `df -h .`.
- **Dependencies:** WH-M0-002.
- **Expected files:** `docs/implementation/project-readiness.md`, optional `scripts/check-environment.sh`.
- **Source:** implementation plan Task 1.
- **Blockers:** Owner action only if macOS permission dialogs must be accepted.

## WH-M0-004

- **Title:** Review milestone 0 and authorize foundation
- **Type:** review
- **Status:** blocked
- **Priority:** P0
- **Scope:** Audit governance, ADR coverage, environment readiness, task consistency, account safety, and the readiness of Milestone 1.
- **Out of scope:** Application code.
- **Acceptance criteria:** Prior tasks are done; no foundation decision is missing; the next ready task is WH-M1-001; backlog statuses are updated; review explicitly states whether implementation may start.
- **Required checks:** All WH-M0-001..003 checks; `git diff --check`; account and remote guard.
- **Dependencies:** WH-M0-001, WH-M0-002, WH-M0-003.
- **Expected files:** `docs/implementation/reviews/m0-review.md`, backlog and roadmap if adjusted.
- **Source:** `docs/implementation/roadmap.md`.
- **Blockers:** Completion of prior Milestone 0 tasks.
