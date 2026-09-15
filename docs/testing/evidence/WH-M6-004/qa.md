# WH-M6-004 privacy and security QA

Date: 2026-09-15

## TDD evidence

- Redaction RED: the new provider-payload regression test failed 24 assertions because localized, describing, reflecting, and presentation values retained the injected private payload.
- Redaction GREEN: 39 selected redaction, OpenAI-client, dictation-presentation, and meeting-processing tests passed with zero failures after provider error bodies were discarded.
- Storage RED: two selected persistence tests failed five assertions because directories were `0755` and a symbolic-link root was accepted.
- Storage GREEN: 33 selected persistence, retention, and screen-capture recorder tests passed with zero failures after private directory creation was centralized.

All private-looking values used by the redaction test are synthetic fixtures. No user key, audio, dictation, transcript, or instruction was read or copied into evidence.

## Static review

- Production Swift sources contain no `print`, `debugPrint`, `dump`, `NSLog`, `os_log`, or `Logger` call.
- No value matching the live OpenAI credential patterns enforced by `scripts/verify.sh` exists in runtime files.
- The only URLSession production implementation is `OpenAIClient`, whose default runtime base is `https://api.openai.com/v1`.
- The only other production external URL is the user-initiated `https://platform.openai.com/api-keys` link.
- `project.yml` declares only the application and its test targets; no package dependency is present. `Config/Whisper.entitlements` is empty.

## Final verification

Run from the repository root without launching UI automation:

```bash
./scripts/verify.sh --skip-ui-tests
```

Result: PASS across all twelve stages. The command executed 295 unit/service tests with zero failures, built both test products, packaged `build/Whisper.app`, and passed deep strict signature verification. ShellCheck was unavailable, so the script used its required `bash -n` fallback for every shell file.

The exception is explicit: UI products were built, but foreground UI tests were not launched so the owner's active desktop session was not disturbed. Manual release UI coverage remains tracked by blocked task `WH-M6-003`.
