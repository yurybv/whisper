# ADR 0007: Insert text through Accessibility with paste fallback

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

Dictation starts while another application owns focus, but Whisper displays nonactivating status UI and may open panels during processing. Target applications expose editable fields inconsistently: some support direct Accessibility text attributes, while web views and custom editors may not.

## Decision

Capture the frontmost application and focused Accessibility element before Whisper presents UI. Prefer direct replacement through the focused element's selected-text attribute. If direct insertion is unsupported, reactivate the captured application, place the result on NSPasteboard, and post Command-V with CGEvent.

Preserve the previous pasteboard before fallback. If the Command-V events can be constructed and posted, wait for the bounded paste delay and restore the prior pasteboard as a best-effort action; CGEvent cannot confirm that the target consumed the command. If Accessibility is denied or event construction or posting cannot proceed, leave the dictated result on the clipboard and tell the user to paste manually. The HUD must never steal focus.

## Consequences

- Native editable controls receive direct insertion without clipboard churn.
- Web and custom editors gain a pragmatic fallback.
- Accessibility permission, focus restoration, paste timing, and best-effort clipboard restoration require explicit state and tests.
- A failed fallback intentionally changes the clipboard so the user's text is not lost.

## Rejected alternatives

- Accessibility insertion only: rejected because not every editable target exposes the required writable attribute.
- Clipboard paste only: rejected because it always disturbs clipboard state and adds avoidable timing and focus risk.
- Typing characters as synthetic key events: rejected because it is slow, layout-dependent, and fragile for Unicode and long text.
- Capturing the target after showing Whisper UI: rejected because the app would capture itself rather than the user's original field.

## References

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Approved error handling](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#error-handling)
- [Implementation plan: Task 8](../../superpowers/plans/2026-08-19-whisper-macos-mvp.md#task-8-focus-capture-and-reliable-text-insertion)
