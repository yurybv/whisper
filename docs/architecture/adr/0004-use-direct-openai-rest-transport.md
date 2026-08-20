# ADR 0004: Use direct OpenAI REST transport

- Status: Accepted
- Date: 2026-08-20
- Applies to: macOS 15+ personal MVP

## Context

The personal MVP uses the owner's OpenAI API key for bounded file transcription, diarized recording transcription, and mode-based text transformation. The client must support cancellation, bounded retries, multipart uploads, precise redaction, and deterministic tests without sending private content over the network.

## Decision

Call OpenAI REST endpoints directly with URLSession behind an `OpenAIClient` protocol. Keep base URLs, model identifiers, response formats, and a conservative 20 MB upload limit in one `OpenAIConfiguration` value. Use `/v1/audio/transcriptions` for audio and the Responses API for transformations.

Read the API key from Keychain immediately before each request. Disable response storage where supported, redact secrets and content from diagnostics, inject the transport and retry clock for tests, and use protocol fakes or URLProtocol interception for all automated verification.

## Consequences

- The app controls multipart encoding, errors, cancellation, retries, and privacy behavior explicitly.
- Feature code is isolated from endpoint DTOs and model-name changes.
- The repository owns request and response maintenance as OpenAI evolves its API.
- There is no proxy server to hide the key; the key remains local in Keychain and is sent only to OpenAI over HTTPS.

## Rejected alternatives

- A community Swift SDK: rejected to avoid an additional dependency and an abstraction that may lag required endpoint fields.
- A custom backend proxy: rejected because accounts, hosted infrastructure, and recurring service costs are outside the personal MVP.
- Provider-neutral abstraction and multiple providers: rejected because only OpenAI is approved for the first release.
- Automated tests against the live API: rejected because tests must not upload audio, transcripts, instructions, or secrets.

## References

- [OpenAI file transcription](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI Responses API](https://developers.openai.com/api/docs/guides/text)
- [Approved OpenAI contract](../../superpowers/specs/2026-08-19-whisper-macos-mvp-design.md#openai-api-contract)
