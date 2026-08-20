# ADR 0001: Use XcodeGen for project generation

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

Whisper needs one application target, unit and UI test targets, explicit bundle metadata, and reproducible build settings. A hand-edited Xcode project is difficult to review as text and can drift when agents or Xcode modify project internals.

## Decision

Keep `project.yml` as the source of truth and generate `Whisper.xcodeproj` with XcodeGen. The bootstrap workflow checks the local Xcode, SDK, and XcodeGen prerequisites before generation. Source folders, resources, build settings, entitlements, schemes, and test targets are declared in the manifest.

The generated project is a derived artifact. It must be regenerated after manifest changes and must not receive hand-authored settings that are absent from `project.yml`.

## Consequences

- Project configuration is reviewable, reproducible, and friendly to small focused commits.
- Agents can bootstrap the same target graph without manipulating Xcode project internals.
- Contributors need XcodeGen before the first build.
- A new Xcode or XcodeGen version may change generated output, so environment readiness and generation are verified explicitly.

## Rejected alternatives

- Hand-maintained `.xcodeproj`: rejected because generated identifiers and project-file churn obscure meaningful changes.
- Swift Package Manager as the only project definition: rejected because the deliverable is a native macOS application bundle with UI tests, resources, plist keys, and entitlements.
- Tuist or a custom generator: rejected because they add more tooling and configuration than this single-app MVP requires.

## References

- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Implementation plan: Task 1](../../superpowers/plans/2026-08-19-whisper-macos-mvp.md#task-1-reproducible-macos-application-scaffold)
