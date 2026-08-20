# OpenDesign Prompt: Whisper macOS Personal MVP

## How to use this file

In OpenDesign:

1. Choose a desktop application or prototype template.
2. Select the Raycast `DESIGN.md` from getdesign.md, saved at the project root, as the active design system.
3. Paste the prompt below as the project request.
4. Attach the seven Superwhisper reference screenshots if OpenDesign accepts image references.

Use the repository-root `DESIGN.md` for import. `raycast-getdesign-source.md` is retained only as an exact archive of the getdesign.md export; the root file contains the same tokens with its malformed YAML theme line normalized for strict parsers.

The Raycast DESIGN.md is the source of truth for the dark surface ladder, text hierarchy, hairlines, compact radii, keycaps, command-palette patterns, and interaction states. This prompt is the source of truth for native macOS product structure, behavior, density, and states. When a visual token conflicts with a macOS convention, preserve macOS usability while applying the selected visual language.

Translate the Raycast system into a native productivity application rather than a marketing website. Do not use the marketing-only red hero stripe, oversized display typography, 96px landing-page section rhythm, pricing components, or promotional app-icon grids. Retain the near-black layered surfaces, one-pixel borders, restrained semantic accents, compact 6–10px radii, keyboard keycaps, and no-shadow elevation model.

---

## Prompt to send

Design a high-fidelity, interactive desktop prototype for a native macOS application named Whisper.

Whisper is a personal menu-bar utility that lets one user dictate into any active text field and record calls from both the Mac system audio and microphone. It uses an OpenAI API key. The experience is keyboard-first, quiet, fast, and trustworthy.

Use the attached Superwhisper screenshots as structural references for sidebar navigation, compact settings cards, mode rows, history density, and dark desktop proportions. Do not use the Superwhisper name, logo, icons, orange branding, locked features, paywalls, or marketing content. Use Whisper branding and neutral SF Symbol-style icons. Apply the Raycast DESIGN.md to visual decisions using the native-app adaptations above.

### Canvas and platform

- Desktop macOS application, not a website or mobile app.
- Primary artboard: 1512 by 982 pixels.
- Minimum useful window: 1120 by 760 pixels.
- Native title bar and macOS traffic-light controls.
- Persistent left sidebar and scrollable detail area.
- Compact menu-bar popover and two floating panels must also be designed.
- Use realistic Russian and English content.

### Navigation

Create five sidebar destinations:

1. Home
2. Modes
3. Recordings
4. History
5. Settings

Show the current microphone in the title bar. Put API and permission problems in context rather than as permanent alarming banners.

### Screen 1: First-run onboarding

Create a four-step setup flow inside the main window.

- Step 1: OpenAI API key. Explain that the key is stored in macOS Keychain. Include a secure field, Save and Test button, success state, invalid-key state, and a link label for where to create a key.
- Step 2: Microphone permission with Not Granted, Request Access, and Granted states.
- Step 3: Screen Recording permission for recording Mac sound.
- Step 4: Accessibility permission for inserting text into the active app.

Include a progress indicator, Back and Continue controls, and a final Ready screen that displays the shortcuts.

### Screen 2: Home

Design a calm status dashboard without productivity statistics.

Show:

- active mode card with Default selected;
- selected microphone;
- OpenAI connection status;
- three permission rows;
- quick actions for Start Dictation, Change Mode, and Record Meeting;
- shortcut keycaps: Right Option, Command-Shift-K, and Command-Shift-R;
- a short recent-history list.

The screen should make the app feel ready without looking like an analytics dashboard.

### Screen 3: Modes list

Show:

- title Modes;
- Create Mode button;
- nondeletable Default row marked Active;
- custom rows named English Translation, Technical Notes, and Concise Reply;
- active indicator;
- overflow menu with Activate, Duplicate, Rename, and Delete.

Rows should feel keyboard-selectable and use concise metadata such as language and last updated time.

### Screen 4: Custom mode editor

Create an editor for English Translation.

Fields:

- Mode name;
- Input language, with Auto selected and Russian available;
- large Custom Instructions text area;
- enabled toggle;
- Save Changes;
- Duplicate Mode;
- Delete Mode.

Use this instruction as realistic content:

The user message contains dictated speech. Translate Russian speech into natural conversational English. Do not answer the message. Do not explain anything. Do not add new information. Output only the transformed text. Preserve technical terms, product names, code identifiers, and abbreviations. Prefer natural English over literal word-for-word translation. Fix obvious speech-recognition mistakes when the intended meaning is clear.

Include unsaved-changes, saving, saved, validation-error, and delete-confirmation states.

### Screen 5: Recordings settings

Create a dedicated Recordings destination.

Show:

- prominent Start Recording control;
- system audio enabled;
- microphone enabled with device selector;
- meeting hotkey;
- maximum supported duration of three hours;
- a large Processing Instructions editor;
- Result Language set to Auto;
- explanation that source audio is stored locally and only audio chunks are sent for transcription.

Use this processing instruction:

Create clear meeting notes in English. Start with a concise summary. Then list decisions, action items with owner when stated, and open questions. Do not invent missing owners or deadlines. Preserve technical terminology.

Include an idle state, active recording state with timer 00:37:18 and audio meters, stopping/finalizing state, and low-disk-space error.

### Screen 6: History list

Create a searchable history grouped by Today and Yesterday.

Include segmented filters All, Dictations, and Recordings.

Realistic rows:

- English Translation dictation: I will check after I finish the token interpolation.
- Default dictation in Russian.
- Product Sync recording, 48 minutes, Ready.
- Architecture Review recording, 1 hour 12 minutes, Processing 7 of 10.
- Failed recording with Retry.

Each row shows type, mode or duration, timestamp, status, and a concise preview. Add contextual actions Copy, Reprocess, Export Text, and Delete.

### Screen 7: Recording detail

Design the Product Sync detail view.

Header:

- editable title;
- date and 48-minute duration;
- Ready status;
- Play Audio, Export Text, Reprocess, and Delete actions.

Content:

- tabs Transcript and Processed Result;
- transcript rows with timestamps and badges You or Others;
- processed result with Summary, Decisions, Action Items, and Open Questions;
- collapsible Processing Details showing the saved instruction and model status;
- compact audio player with separate microphone and system-audio availability.

Include Ready, Transcribing, Processing, Failed, and Reprocessing states.

### Screen 8: Settings

Create grouped cards for:

- OpenAI API key: masked value, Connected, Test, Replace, Remove;
- Audio input: microphone selector and input level;
- Keyboard shortcuts: Push to Talk, Change Mode, Record Meeting, Cancel;
- Application: Launch at Login, Sound Effects, Keep Recordings Forever;
- Permissions: Microphone, Screen Recording, Accessibility;
- About: version and local-build label.

Shortcut recording controls must show conflict and reset states.

### Overlay A: Push-to-talk HUD

Create a nonactivating floating panel near the bottom center of the display.

States:

- listening: active mode name, live waveform, Release Right Option to finish;
- transcribing: spinner or waveform transition;
- processing: mode-specific status;
- inserted: brief success confirmation;
- error: concise message and Copy Text action;
- cancelled.

It must remain readable over light and dark applications without becoming visually loud.

### Overlay B: Mode switcher

Create a compact command-palette panel opened by Command-Shift-K.

- Search field focused by default;
- mode list with active checkmark;
- Default, English Translation, Technical Notes, Concise Reply;
- arrow-key selection;
- Return to activate and Escape to close;
- footer with shortcut hints.

### Menu-bar popover

Design a narrow menu-bar popover showing:

- current mode;
- Start Dictation;
- Change Mode;
- Start or Stop Meeting Recording;
- latest history item;
- Open Whisper;
- Quit.

When a meeting is recording, replace the normal menu-bar icon state with a visible recording indicator and show the timer.

### Interaction requirements

Prototype the following flows:

1. Onboarding from API key through permissions to Ready.
2. Create and save a custom mode.
3. Open the mode switcher and activate English Translation.
4. Move the push-to-talk HUD through listening, transcribing, processing, and inserted.
5. Start and stop a meeting recording.
6. Move a recording through transcribing, processing, and ready.
7. Open a recording detail and switch between Transcript and Processed Result.
8. Trigger API-key, permission, network, and low-disk errors.

### Quality bar

- Match native macOS information density and alignment.
- Preserve a clear keyboard-first hierarchy.
- Do not make every surface a floating card.
- Do not use oversized website headings or landing-page composition.
- Avoid decorative gradients, illustrations, and charts unless the selected DESIGN.md explicitly requires them.
- Use consistent sidebar width, card padding, row height, form width, and toolbar alignment.
- Provide visible focus, hover, pressed, disabled, loading, success, warning, and error states.
- Use text plus symbols for recording and errors; never communicate them by color alone.
- Use realistic copy, not lorem ipsum.
- The prototype should feel production-ready and coherent across all screens and overlays.

---

## Expected deliverable

Return one navigable desktop prototype containing all eight screens, two overlays, and the menu-bar popover. Include a compact component/state inventory so the implementation team can map the design to SwiftUI components.
