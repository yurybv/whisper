# Whisper macOS Personal MVP Design

Date: 2026-08-19  
Status: approved direction, implementation-ready  
Audience: product designer and implementation engineer

## Product goal

Whisper is a personal macOS menu-bar utility that turns speech into text in any active application and records calls from the microphone and Mac system audio. It uses the user's OpenAI API key and keeps application data locally.

The MVP is successful when the user can:

1. Hold Right Option, dictate in Russian or English, release the key, and receive polished text in the previously focused field.
2. Switch the active mode with Command-Shift-K.
3. Create any number of custom modes with persistent natural-language instructions, including a Russian-to-English mode.
4. Start and stop a call recording with Command-Shift-R.
5. Recover a complete recording after up to three hours, even if network processing fails.
6. Read a chronological transcript labeled You and Others, plus a separately processed result based on one global recording instruction.

## Product boundaries

This is a personal, local MVP for one Apple Silicon Mac running macOS 26.4.1. The app is built with Swift and SwiftUI, signed ad hoc, and installed outside the Mac App Store. The user may need to right-click the app and choose Open on first launch.

The first release does not include:

- accounts, subscriptions, analytics, or cloud sync;
- Mac App Store distribution or Apple notarization;
- Windows, Linux, iPhone, or Intel Mac support;
- local speech models or multiple AI providers;
- a model library, vocabulary screen, WPM statistics, themes, or automatic updates;
- app-specific mode activation;
- recognition of individual remote participants beyond the group label Others.

## Platform and technology

- macOS deployment target: macOS 15 or newer.
- Development environment: Xcode 26.6, Swift 6.3, SwiftUI and AppKit.
- UI: SwiftUI for application screens; AppKit panels for nonactivating overlays.
- Persistence: SwiftData for metadata; files under Application Support for audio.
- Secrets: macOS Keychain.
- Microphone dictation: AVAudioEngine.
- System and microphone call capture: ScreenCaptureKit.
- Global shortcuts: Quartz CGEventTap.
- Text insertion: Accessibility APIs with a clipboard and Command-V fallback.
- OpenAI transport: URLSession with direct REST requests and no third-party SDK.

## Visual direction

The selected getdesign.md system is Raycast, stored as `DESIGN.md` at the repository root. It is the visual-token source for the MVP and is combined with the attached Superwhisper screenshots, which remain the structural reference for the sidebar, settings cards, mode rows, history density, and recording surfaces.

Use the Raycast system as a native productivity UI rather than reproducing its marketing website:

- dark-only near-black canvas with a four-step surface ladder;
- one-pixel hairline borders instead of card shadows;
- compact 6–10px radii for controls and cards, with 16px reserved for large overlays;
- small physical-key keycaps for shortcuts;
- command-palette structure for the mode switcher;
- restrained blue, green, yellow, and red semantic colors;
- SF Pro and native macOS controls where platform conventions are stronger than the source system.

Do not use the Raycast marketing hero stripe, oversized display typography, pricing components, promotional icon grids, or 96px landing-page section rhythm.

## Information architecture

The main window uses a sidebar with five destinations.

### Home

Shows the active mode, selected microphone, OpenAI connection status, permission status, the three shortcuts, and quick actions. It does not show productivity statistics.

### Modes

Shows a nondeletable Default mode and any number of custom modes.

Each custom mode contains:

- name;
- enabled state;
- natural-language instructions;
- input language set to Auto or a specific supported language;
- created and updated timestamps.

Actions are Create, Duplicate, Rename, Activate, and Delete. Deleting the active mode activates Default.

### Recordings

Contains:

- Start or Stop Recording;
- system audio enabled and microphone enabled indicators;
- selected microphone;
- recording hotkey;
- a single Processing Instructions editor;
- a result language selector with Auto as the default;
- a short explanation that source audio remains local except for chunks sent to OpenAI.

### History

Contains both dictations and recordings with a type filter, search, date grouping, and status. Dictation details expose original transcript, transformed result, mode snapshot, target app, copy, and delete. Recording details expose audio playback, You/Others transcript, processed result, progress, retry, reprocess, copy, export text, and delete.

### Settings

Contains:

- masked OpenAI API key with Save, Replace, Remove, and Test Connection;
- selected microphone;
- Push to Talk, Change Mode, Record Meeting, and Cancel shortcuts;
- launch at login;
- sound effects on or off;
- retention policy, defaulting to Forever;
- permission rows for Microphone, Screen Recording, and Accessibility with Open System Settings actions.

## Onboarding

The first launch opens a four-step setup:

1. Explain local processing boundaries and request the OpenAI API key.
2. Request microphone access.
3. Request Screen Recording access.
4. Request Accessibility access and verify all permissions.

The app remains usable for history and mode editing when a permission is missing. Features that require the missing permission explain the exact fix instead of failing silently.

## Dictation behavior

### Default mode

Default always exists and cannot be renamed or deleted. It detects the spoken language and performs light cleanup:

- preserve the spoken language;
- add punctuation and paragraphs;
- remove obvious filler words and accidental repetitions;
- correct obvious recognition errors;
- preserve meaning, tone, technical terms, names, code identifiers, and abbreviations;
- return only the final text.

### Custom modes

Custom mode instructions are applied after transcription. Every request also receives fixed safety instructions:

- transform the transcript rather than answer it;
- do not add facts that were not dictated;
- return only the transformed text;
- preserve technical terms unless the custom instructions explicitly request otherwise.

The user's Russian-to-English mode is represented as a normal custom mode. No translation-specific code path is required.

### Push-to-talk flow

1. A CGEventTap detects Right Option down.
2. The app records the frontmost application and focused element.
3. A nonactivating HUD appears with the active mode and audio level.
4. AVAudioEngine writes a temporary WAV file.
5. Right Option up stops recording.
6. The app sends the file to OpenAI file transcription.
7. The app sends the transcript and mode instructions to the Responses API.
8. The app inserts the final text into the captured focused element.
9. The app stores a history item and removes the temporary audio.

Escape cancels recording. Empty or silent recordings do not call OpenAI.

### Mode switcher

Command-Shift-K opens a compact keyboard-first panel. Search is focused. Arrow keys change selection, Return activates, and Escape closes. Closing the panel restores focus to the application active before the panel opened.

## Call recording behavior

Command-Shift-R toggles a long-running recording. The app captures ScreenCaptureKit audio and microphone outputs into separate AAC M4A files. The app excludes its own sound effects from system capture.

The recording writes continuously to Application Support, never to memory. A small persistent HUD and the menu-bar icon show duration and stop control. The maximum supported duration is three hours.

On stop:

1. The app finalizes both M4A files.
2. Each track is split into 20-minute chunks with a one-second overlap. Every chunk remains below the OpenAI 25 MB upload limit at the chosen AAC bitrate.
3. Chunks are transcribed with speaker-segment timestamps.
4. Microphone segments are labeled You; system-audio segments are labeled Others.
5. Chunk offsets are added, overlap duplicates are removed, and all segments are sorted chronologically.
6. Adjacent segments from the same source are coalesced when the gap is less than five seconds.
7. The merged transcript is processed once with the saved recording instruction.
8. Raw audio, transcript, processed output, and the instruction snapshot remain available in History.

The recording is considered safely captured as soon as both audio writers finalize. Transcription and processing are resumable background jobs.

## OpenAI API contract

The API key is read from Keychain immediately before a request and is never persisted in SwiftData, UserDefaults, logs, crash text, or history.

Central model configuration:

- dictation transcription: gpt-transcribe;
- recording timestamp transcription: gpt-4o-transcribe-diarize with diarized_json and automatic chunking;
- text cleanup and mode transformation: gpt-5.6-luna through the Responses API;
- request storage: disabled where the endpoint supports store=false.

Model identifiers are centralized in one configuration type so they can be updated without changing feature code.

The client uses exponential retry for HTTP 429 and transient 5xx responses. Authentication errors stop immediately and direct the user to Settings. Every request has a cancellation handle.

## Data model

### Mode

- id: UUID
- name: String
- instructions: String
- languageHint: optional String
- isDefault: Bool
- isEnabled: Bool
- sortIndex: Int
- createdAt: Date
- updatedAt: Date

Invariants: exactly one Default mode exists; Default is enabled and cannot be deleted; mode names are nonempty and unique after trimming.

### DictationRecord

- id: UUID
- createdAt: Date
- duration: TimeInterval
- modeID: optional UUID
- modeNameSnapshot: String
- modeInstructionsSnapshot: String
- detectedLanguages: array of String
- originalText: String
- outputText: String
- targetApplicationBundleID: optional String
- status: processing, ready, failed, or cancelled
- errorMessage: optional String

### MeetingRecord

- id: UUID
- title: String
- startedAt: Date
- endedAt: optional Date
- duration: TimeInterval
- status: recording, captured, transcribing, processing, ready, or failed
- progressCompleted: Int
- progressTotal: Int
- instructionsSnapshot: String
- resultLanguage: optional String
- microphoneRelativePath: String
- systemAudioRelativePath: String
- processedText: String
- errorMessage: optional String

### TranscriptSegment

- id: UUID
- meetingID: UUID
- source: you or others
- startTime: TimeInterval
- endTime: TimeInterval
- text: String

### UserDefaults settings

- activeModeID;
- selectedMicrophoneID;
- three configurable shortcuts plus Escape cancel;
- recording instructions;
- recording result language;
- launch at login;
- sound effects enabled;
- audio retention policy;
- onboarding completion.

## Storage layout

Application Support uses this shape:

Whisper/
  Recordings/
    meeting-UUID/
      microphone.m4a
      system.m4a
      chunks/
  Temporary/

Chunk files are deleted after their transcript is persisted. Failed jobs keep only the chunks still required for retry. Deleting a meeting removes its database rows and its meeting directory after confirmation.

## State machines

Dictation states:

idle → recording → transcribing → transforming → inserting → completed → idle

Any active state can move to cancelled or failed, then back to idle. Only one dictation may run at a time.

Meeting states:

idle → recording → finalizing → captured → transcribing → processing → ready

Captured, transcribing, and processing records survive app relaunch. A startup recovery service resumes incomplete jobs. Starting a meeting while dictation is active is rejected with a clear HUD message, and push-to-talk is disabled during a meeting.

## Error handling

- Missing API key: open Settings and keep captured audio.
- Invalid API key: mark the item failed without retry.
- No network: keep the item captured and expose Retry.
- Rate limit or server failure: retry with backoff, then preserve the resumable job.
- Lost microphone device: stop safely, finalize available audio, and explain which track failed.
- Screen capture revoked: stop the meeting and preserve microphone audio.
- Accessibility denied: copy the result to clipboard and show Paste manually.
- Unsupported focused field: try clipboard plus Command-V; if that fails, leave text on the clipboard.
- Disk space below 2 GB before a meeting: block recording with a storage warning.
- App terminated during recording: recover finalized data when possible; unfinished container files are marked interrupted and never deleted automatically.

## UI states and accessibility

Every primary screen includes loading, empty, populated, error, and disabled states. Recording and processing state must never rely on color alone. Controls use SF Symbols plus text, keyboard focus rings, VoiceOver labels, and a minimum 44-point hit target where practical.

The recording HUD never steals focus. The mode switcher intentionally becomes key only while open and restores the previous app afterward.

## Testing strategy

Unit tests cover mode invariants, hotkey state transitions, multipart request construction, Responses API decoding, transcript merging, overlap removal, chunk planning, retry policy, state-machine transitions, and persistence recovery.

Integration tests use protocol fakes for AVAudioEngine, ScreenCaptureKit writers, Keychain, Accessibility insertion, and URLSession. No automated test sends audio or secrets to OpenAI.

Manual acceptance tests cover:

- TextEdit, Notes, Safari, Slack, and VS Code insertion;
- Russian and English Default dictation;
- the Russian-to-English custom mode;
- cancel, silence, offline, invalid-key, and revoked-permission cases;
- system audio plus microphone recording;
- app relaunch during captured/transcribing states;
- a synthetic three-hour capture and disk growth;
- first-launch Gatekeeper and permission instructions.

## Distribution

The repository provides a local packaging script that generates Whisper.app and signs it ad hoc. The README explains:

1. build the app;
2. move it to Applications;
3. right-click and choose Open if Gatekeeper warns;
4. complete onboarding permissions;
5. paste and test the OpenAI API key.

Notarization and automatic updating remain outside this MVP.

## Sources

- OpenAI file transcription guide: https://developers.openai.com/api/docs/guides/speech-to-text
- OpenAI model catalog: https://developers.openai.com/api/docs/models
- Apple ScreenCaptureKit sample: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- Apple CGEventTap documentation: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate
