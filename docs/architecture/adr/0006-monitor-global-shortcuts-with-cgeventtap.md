# ADR 0006: Monitor global shortcuts with CGEventTap

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

Push to talk depends on the physical press and release of Right Option even when Whisper is not focused. The mode and meeting shortcuts also need global key events, while the shortcut recorder must distinguish left and right modifiers, suppress repeat, and reject conflicts.

## Decision

Create a Quartz session event tap for key-down, key-up, and flags-changed events. Run the callback on a dedicated run-loop thread, normalize events immediately, and pass them to an actor-owned pure state machine. Re-enable a tap disabled by timeout or user input.

Identify Right Option by its physical key code and emit exactly one pressed and released transition. Store shortcut definitions as domain values so conflict validation, defaults, recording, and runtime matching share the same rules.

## Consequences

- Modifier-only push to talk and release semantics work outside the app.
- Accessibility permission and event-tap lifecycle status become explicit prerequisites.
- The callback must perform minimal work and must not own feature state.
- Keyboard layouts and reserved macOS shortcuts require validation in the shortcut domain.

## Rejected alternatives

- NSEvent global monitors: rejected because they do not provide the same low-level physical transition and recovery control required by modifier-only push to talk.
- Carbon hot-key registration: rejected because the design needs press and release semantics for a standalone modifier as well as modern configurable shortcuts.
- Polling modifier state: rejected because it wastes resources and can miss transitions during focus or sleep changes.
- App-local SwiftUI commands: rejected because dictation must start while another application is focused.

## References

- [Apple CGEvent tap creation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [Approved push-to-talk flow](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#push-to-talk-flow)
- [Implementation plan: Task 9](../../superpowers/plans/2026-08-19-whisper-macos-mvp.md#task-9-global-shortcuts-and-shortcut-recorder)
