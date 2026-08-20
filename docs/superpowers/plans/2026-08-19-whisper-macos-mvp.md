# Whisper macOS Personal MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a personal native macOS menu-bar app that provides mode-based push-to-talk dictation, automatic text insertion, and resumable microphone plus system-audio call transcription.

**Architecture:** A SwiftUI application owns feature state while focused services isolate hotkeys, audio capture, Accessibility insertion, persistence, and OpenAI networking behind protocols. SwiftData stores metadata, Application Support stores recordings, and Keychain stores the API key. Dictation is a short state machine; meeting capture and post-processing are a durable, resumable job.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, SwiftData, AVFoundation, ScreenCaptureKit, CoreGraphics, ApplicationServices, Security, ServiceManagement, URLSession, XCTest, XcodeGen.

**Spec:** docs/superpowers/specs/2026-08-19-whisper-macos-mvp-design.md

## Global Constraints

- Target macOS 15 or newer and Apple Silicon.
- Build with Xcode 26.6 and Swift 6 language mode.
- Keep App Sandbox disabled for the personal MVP.
- Sign local builds ad hoc; do not add App Store, notarization, or updater work.
- Store the OpenAI API key only in macOS Keychain.
- Store audio only under Application Support/Whisper.
- Never log the API key, request Authorization header, dictated text, transcripts, or processing instructions.
- Use gpt-transcribe for dictation, gpt-4o-transcribe-diarize for timestamped recording chunks, and gpt-5.6-luna for text transformation.
- Keep OpenAI model identifiers centralized in OpenAIConfiguration.
- Limit uploaded audio files to 20 MB even though the API limit is 25 MB.
- Write recordings continuously to disk and support up to three hours.
- Use Right Option for push-to-talk, Command-Shift-K for the mode switcher, Command-Shift-R for meeting recording, and Escape for cancel by default.
- Preserve the original focused application before showing any panel.
- UI copy is English in the MVP; dictated content may be any supported language.
- Use the repository-root Raycast DESIGN.md as the visual-token source and the Superwhisper screenshots as the structural source. The approved OpenDesign prototype supersedes only the screen-level composition when it becomes available.

## File map

The plan creates these responsibility groups:

- project.yml, Config, Resources: reproducible Xcode project, bundle metadata, entitlements, and assets.
- Sources/WhisperApp: app entry, dependency composition, menu bar, and window orchestration.
- Sources/Core: shared domain values, state machines, settings, errors, and design tokens.
- Sources/Persistence: SwiftData entities, repositories, paths, and recovery queries.
- Sources/OpenAI: REST transport, multipart encoding, request and response DTOs, and retry.
- Sources/Audio: microphone capture, meeting capture, file writers, chunk export, and meters.
- Sources/Dictation: push-to-talk orchestration, mode transformation, and insertion coordination.
- Sources/Meetings: transcript merge, durable processing jobs, and recovery.
- Sources/Hotkeys: event tap, shortcut definitions, and shortcut state machine.
- Sources/Accessibility: focused-target capture and insertion.
- Sources/UI: onboarding, main destinations, reusable components, HUD, and mode switcher.
- Tests/WhisperTests: deterministic unit and service integration tests using fakes.
- Tests/WhisperUITests: navigation and form smoke tests.
- scripts: project generation, local packaging, and acceptance helpers.

---

### Task 1: Reproducible macOS application scaffold

**Files:**

- Create: project.yml
- Create: Config/Whisper.entitlements
- Create: Resources/Info.plist
- Create: Sources/WhisperApp/WhisperApp.swift
- Create: Sources/WhisperApp/AppDelegate.swift
- Create: Sources/Core/DesignTokens.swift
- Create: Tests/WhisperTests/SmokeTests.swift
- Create: scripts/bootstrap.sh

**Interfaces:**

- Produces: executable target Whisper, unit-test target WhisperTests, UI-test target WhisperUITests, bundle identifier dev.yury.whisper, and macOS 15 deployment target.
- Consumes: XcodeGen available through Homebrew.

- [ ] **Step 1: Write the project smoke test**

~~~swift
import XCTest
@testable import Whisper

final class SmokeTests: XCTestCase {
    func testApplicationBundleIdentifier() {
        XCTAssertEqual(Bundle(for: AppDelegate.self).bundleIdentifier, "dev.yury.whisper")
    }
}
~~~

- [ ] **Step 2: Create the XcodeGen manifest**

Use this target shape in project.yml:

~~~yaml
name: Whisper
options:
  bundleIdPrefix: dev.yury
  deploymentTarget:
    macOS: "15.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "15.0"
targets:
  Whisper:
    type: application
    platform: macOS
    sources:
      - Sources
    resources:
      - Resources
    info:
      path: Resources/Info.plist
    entitlements:
      path: Config/Whisper.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.yury.whisper
        PRODUCT_NAME: Whisper
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_IDENTITY: "-"
  WhisperTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/WhisperTests
    dependencies:
      - target: Whisper
  WhisperUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - Tests/WhisperUITests
    dependencies:
      - target: Whisper
schemes:
  Whisper:
    build:
      targets:
        Whisper: all
        WhisperTests: [test]
        WhisperUITests: [test]
    test:
      targets:
        - WhisperTests
        - WhisperUITests
~~~

Info.plist must include NSMicrophoneUsageDescription, NSScreenCaptureUsageDescription, LSUIElement set to true, and CFBundleDisplayName set to Whisper. Leave the app unsandboxed and use an empty entitlement dictionary.

- [ ] **Step 3: Create the app entry and visual baseline**

WhisperApp creates one settings-style WindowGroup and installs AppDelegate. DesignTokens defines exact baseline values:

~~~swift
import SwiftUI

enum DesignTokens {
    static let sidebarWidth: CGFloat = 248
    static let contentMaxWidth: CGFloat = 1040
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
    static let overlayRadius: CGFloat = 16
    static let rowHeight: CGFloat = 56
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let canvas = Color(red: 7/255, green: 8/255, blue: 10/255)
    static let sidebar = Color(red: 13/255, green: 13/255, blue: 13/255)
    static let surface = Color(red: 13/255, green: 13/255, blue: 13/255)
    static let surfaceElevated = Color(red: 16/255, green: 17/255, blue: 17/255)
    static let surfaceCard = Color(red: 18/255, green: 18/255, blue: 18/255)
    static let selected = surfaceCard
    static let border = Color(red: 36/255, green: 39/255, blue: 40/255)
    static let primaryText = Color(red: 244/255, green: 244/255, blue: 246/255)
    static let secondaryText = Color(red: 205/255, green: 205/255, blue: 205/255)
    static let mutedText = Color(red: 156/255, green: 156/255, blue: 157/255)
    static let accent = Color(red: 87/255, green: 193/255, blue: 255/255)
    static let success = Color(red: 89/255, green: 212/255, blue: 153/255)
    static let warning = Color(red: 255/255, green: 197/255, blue: 51/255)
    static let danger = Color(red: 255/255, green: 97/255, blue: 97/255)
}
~~~

Force the main window and nonactivating panels into dark appearance for the MVP. Use SF Pro through SwiftUI system fonts; do not bundle Inter. Do not implement the Raycast marketing hero stripe or its landing-page spacing rules.

- [ ] **Step 4: Add bootstrap script**

scripts/bootstrap.sh checks for XcodeGen, installs it with brew only after the user runs the script, generates Whisper.xcodeproj, and prints the xcodebuild command. Make the script fail if Xcode 26 or the macOS 15 SDK is unavailable.

- [ ] **Step 5: Generate and build**

Run:

~~~bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" build
~~~

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the smoke test**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/SmokeTests
~~~

Expected: one passing test.

- [ ] **Step 7: Commit**

~~~bash
git add project.yml Config Resources Sources/WhisperApp Sources/Core Tests scripts/bootstrap.sh
git commit -m "build(macos): scaffold native Whisper app" \
  -m $'- Generate the Xcode project reproducibly with XcodeGen\n- Add the application, test targets, entitlements, and baseline tokens'
~~~

---

### Task 2: Domain models, mode invariants, and settings

**Files:**

- Create: Sources/Core/ModeDefinition.swift
- Create: Sources/Core/ModeRules.swift
- Create: Sources/Core/AppSettings.swift
- Create: Sources/Core/Shortcut.swift
- Create: Sources/Core/FeatureError.swift
- Test: Tests/WhisperTests/Core/ModeRulesTests.swift
- Test: Tests/WhisperTests/Core/ShortcutTests.swift

**Interfaces:**

- Produces: ModeDefinition, ModeDraft, ModeRules.validate(_:existing:), Shortcut, Shortcut.Key, Shortcut.Modifiers, AppSettings.
- Consumes: Foundation only.

- [ ] **Step 1: Write failing mode-rule tests**

~~~swift
import XCTest
@testable import Whisper

final class ModeRulesTests: XCTestCase {
    func testRejectsBlankName() {
        let draft = ModeDraft(name: "  ", instructions: "Translate", languageHint: nil)
        XCTAssertThrowsError(try ModeRules.validate(draft, existing: [])) {
            XCTAssertEqual($0 as? ModeValidationError, .blankName)
        }
    }

    func testRejectsTrimmedDuplicateName() {
        let existing = [ModeDefinition.defaultMode,
                        ModeDefinition(id: UUID(), name: "English", instructions: "Translate", languageHint: nil, isDefault: false, isEnabled: true)]
        let draft = ModeDraft(name: " english ", instructions: "Translate", languageHint: nil)
        XCTAssertThrowsError(try ModeRules.validate(draft, existing: existing))
    }

    func testDefaultModeIsStable() {
        XCTAssertTrue(ModeDefinition.defaultMode.isDefault)
        XCTAssertEqual(ModeDefinition.defaultMode.name, "Default")
    }
}
~~~

- [ ] **Step 2: Implement mode domain types**

ModeDefinition is Sendable, Codable, Identifiable, and Equatable. ModeRules trims names, compares case-insensitively, requires nonempty custom instructions, and returns a normalized ModeDefinition. ModeValidationError cases are blankName, duplicateName, blankInstructions, and defaultMutation.

- [ ] **Step 3: Write shortcut round-trip tests**

~~~swift
func testDefaultShortcutsRoundTripThroughJSON() throws {
    let values = AppSettings.defaults.shortcuts
    let data = try JSONEncoder().encode(values)
    XCTAssertEqual(try JSONDecoder().decode([ShortcutAction: Shortcut].self, from: data), values)
}
~~~

- [ ] **Step 4: Implement settings defaults**

AppSettings.defaults must use:

- pushToTalk: Right Option modifier key code 61;
- changeMode: Command-Shift-K;
- recordMeeting: Command-Shift-R;
- cancel: Escape;
- launchAtLogin: false;
- soundEffects: true;
- retention: forever;
- recordingInstructions: the approved meeting-notes instruction from the spec;
- resultLanguage: nil for Auto.

- [ ] **Step 5: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/ModeRulesTests -only-testing:WhisperTests/ShortcutTests
~~~

Expected: all tests pass.

- [ ] **Step 6: Commit**

~~~bash
git add Sources/Core Tests/WhisperTests/Core
git commit -m "feat(core): define modes and app settings" \
  -m $'- Add domain values and default-mode invariants\n- Persist validated user preferences and shortcut defaults'
~~~

---

### Task 3: SwiftData persistence and file layout

**Files:**

- Create: Sources/Persistence/Entities/ModeEntity.swift
- Create: Sources/Persistence/Entities/DictationEntity.swift
- Create: Sources/Persistence/Entities/MeetingEntity.swift
- Create: Sources/Persistence/Entities/TranscriptSegmentEntity.swift
- Create: Sources/Persistence/PersistenceController.swift
- Create: Sources/Persistence/ModeRepository.swift
- Create: Sources/Persistence/HistoryRepository.swift
- Create: Sources/Persistence/AppPaths.swift
- Test: Tests/WhisperTests/Persistence/PersistenceTests.swift

**Interfaces:**

- Produces: PersistenceController.container, ModeRepository, HistoryRepository, AppPaths.recordingDirectory(for:), seedDefaultMode().
- Consumes: domain types from Task 2.

- [ ] **Step 1: Write failing in-memory persistence tests**

~~~swift
@MainActor
func testSeedsExactlyOneDefaultMode() async throws {
    let controller = try PersistenceController(inMemory: true)
    let repository = ModeRepository(context: controller.container.mainContext)
    try repository.seedDefaultMode()
    try repository.seedDefaultMode()
    let modes = try repository.fetchAll()
    XCTAssertEqual(modes.filter(\.isDefault).count, 1)
}

@MainActor
func testDeletingActiveCustomModeFallsBackToDefault() async throws {
    let controller = try PersistenceController(inMemory: true)
    let repository = ModeRepository(context: controller.container.mainContext)
    try repository.seedDefaultMode()
    let custom = try repository.create(ModeDraft(name: "English", instructions: "Translate to English.", languageHint: "ru"))
    try repository.activate(custom.id)
    try repository.delete(custom.id)
    XCTAssertEqual(try repository.activeMode().name, "Default")
}
~~~

- [ ] **Step 2: Implement SwiftData entities**

Store enum values as raw strings. TranscriptSegmentEntity has a required relationship to MeetingEntity with cascade deletion. ModeEntity uses a unique id and stores normalizedName for case-insensitive uniqueness checks performed by the repository.

- [ ] **Step 3: Implement repositories**

ModeRepository is isolated to MainActor because it owns a ModelContext. HistoryRepository provides:

~~~swift
@MainActor
protocol HistoryRepositoryProtocol {
    func createDictation(_ draft: DictationDraft) throws -> UUID
    func updateDictation(id: UUID, mutation: DictationMutation) throws
    func createMeeting(_ draft: MeetingDraft) throws -> UUID
    func updateMeeting(id: UUID, mutation: MeetingMutation) throws
    func replaceSegments(meetingID: UUID, segments: [TranscriptSegment]) throws
    func incompleteMeetings() throws -> [MeetingSnapshot]
    func deleteDictation(id: UUID) throws
    func deleteMeeting(id: UUID) throws
}
~~~

- [ ] **Step 4: Implement Application Support paths**

AppPaths creates:

- Library/Application Support/Whisper/Recordings;
- Library/Application Support/Whisper/Temporary.

Directory methods accept a FileManager dependency for tests. recordingDirectory(for:) produces meeting-UUID and rejects paths outside the Whisper root.

- [ ] **Step 5: Add file-layout tests**

Use a unique directory under FileManager.default.temporaryDirectory. Assert that paths are created under the injected root and that deleting a meeting removes only that meeting directory.

- [ ] **Step 6: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/PersistenceTests
~~~

Expected: all persistence and path tests pass.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/Persistence Tests/WhisperTests/Persistence
git commit -m "feat(persistence): store modes and history locally" \
  -m $'- Add SwiftData entities and repository boundaries\n- Create deterministic Application Support paths and recovery queries'
~~~

---

### Task 4: Keychain, permissions, and launch-at-login services

**Files:**

- Create: Sources/Core/SecureStore.swift
- Create: Sources/Core/KeychainSecureStore.swift
- Create: Sources/Core/PermissionService.swift
- Create: Sources/Core/LaunchAtLoginService.swift
- Test: Tests/WhisperTests/Core/KeychainSecureStoreTests.swift
- Test: Tests/WhisperTests/Core/PermissionServiceTests.swift

**Interfaces:**

- Produces: SecureStore.readOpenAIKey(), saveOpenAIKey(_:), deleteOpenAIKey(); PermissionSnapshot; PermissionService.request(_:); LaunchAtLoginService.setEnabled(_:).
- Consumes: Security, AVFoundation, CoreGraphics, ApplicationServices, ServiceManagement.

- [ ] **Step 1: Define secret-store contract and fake**

~~~swift
protocol SecureStore: Sendable {
    func readOpenAIKey() throws -> String?
    func saveOpenAIKey(_ value: String) throws
    func deleteOpenAIKey() throws
}

actor InMemorySecureStore: SecureStore {
    private var value: String?
    func readOpenAIKey() -> String? { value }
    func saveOpenAIKey(_ value: String) { self.value = value }
    func deleteOpenAIKey() { value = nil }
}
~~~

- [ ] **Step 2: Write Keychain lifecycle test**

Use a test-only KeychainSecureStore service name with a UUID. Save, replace, read, delete, and assert nil. The test tearDown deletes that test item.

- [ ] **Step 3: Implement Keychain store**

Use kSecClassGenericPassword, service dev.yury.whisper.openai, account api-key, and kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. Map errSecItemNotFound to nil and every other unexpected OSStatus to FeatureError.keychain.

- [ ] **Step 4: Implement permission snapshots**

PermissionKind cases are microphone, screenRecording, and accessibility. PermissionState cases are granted, denied, and notDetermined. Use:

- AVCaptureDevice.authorizationStatus(for: .audio);
- CGPreflightScreenCaptureAccess();
- AXIsProcessTrusted();

Request methods use AVCaptureDevice.requestAccess, CGRequestScreenCaptureAccess, and AXIsProcessTrustedWithOptions with kAXTrustedCheckOptionPrompt.

- [ ] **Step 5: Implement launch-at-login wrapper**

Wrap SMAppService.mainApp.register() and unregister(). Expose current status and map requiresApproval to an Open Login Items action.

- [ ] **Step 6: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/KeychainSecureStoreTests -only-testing:WhisperTests/PermissionServiceTests
~~~

Expected: tests pass without prompting because permission APIs are wrapped by fakes in unit tests.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/Core Tests/WhisperTests/Core
git commit -m "feat(settings): secure API key and permissions" \
  -m $'- Store the OpenAI API key in Keychain\n- Add permission status and launch-at-login services'
~~~

---

### Task 5: OpenAI REST client and retry policy

**Files:**

- Create: Sources/OpenAI/OpenAIConfiguration.swift
- Create: Sources/OpenAI/OpenAIClient.swift
- Create: Sources/OpenAI/MultipartFormData.swift
- Create: Sources/OpenAI/OpenAIModels.swift
- Create: Sources/OpenAI/RetryPolicy.swift
- Test: Tests/WhisperTests/OpenAI/OpenAIClientTests.swift
- Test: Tests/WhisperTests/OpenAI/MultipartFormDataTests.swift
- Test: Tests/WhisperTests/OpenAI/RetryPolicyTests.swift

**Interfaces:**

- Produces: transcribe(fileURL:languageHint:prompt:), transcribeDiarized(fileURL:), transform(text:instructions:), testConnection().
- Consumes: SecureStore from Task 4 and URLSessionProtocol.

- [ ] **Step 1: Write request-construction tests**

Use a custom URLProtocol to capture requests. Assert:

- POST /v1/audio/transcriptions;
- Authorization uses the fake key;
- multipart contains model gpt-transcribe and the audio bytes;
- optional language context is omitted for Auto;
- no secret appears in error descriptions.

~~~swift
func testDictationTranscriptionUsesConfiguredModel() async throws {
    let request = try await recorder.capture {
        _ = try await client.transcribe(fileURL: fixtureURL, languageHint: nil, prompt: nil)
    }
    let body = try XCTUnwrap(request.httpBody)
    XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("gpt-transcribe"))
}
~~~

- [ ] **Step 2: Implement centralized configuration**

~~~swift
struct OpenAIConfiguration: Sendable {
    let baseURL = URL(string: "https://api.openai.com/v1")!
    let dictationModel = "gpt-transcribe"
    let meetingModel = "gpt-4o-transcribe-diarize"
    let transformModel = "gpt-5.6-luna"
    let maximumUploadBytes = 20 * 1024 * 1024
}
~~~

- [ ] **Step 3: Implement multipart encoding**

MultipartFormData produces a random boundary, CRLF-correct form fields, filename, MIME type, and body. Reject a file over maximumUploadBytes before reading it into request data.

- [ ] **Step 4: Implement decoding**

Define:

~~~swift
struct TranscriptionResponse: Decodable, Sendable {
    let text: String
    let languages: [DetectedLanguage]?
}

struct DiarizedTranscriptionResponse: Decodable, Sendable {
    let text: String?
    let segments: [DiarizedSegment]
}

struct DiarizedSegment: Decodable, Sendable {
    let speaker: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}
~~~

The diarized request includes response_format=diarized_json and chunking_strategy=auto. The Responses request includes model gpt-5.6-luna, store false, fixed developer instructions, user input text, and low text verbosity.

- [ ] **Step 5: Implement retry**

Retry HTTP 429, 500, 502, 503, 504, URLError.timedOut, networkConnectionLost, and notConnectedToInternet. Use delays 1, 2, and 4 seconds plus injected jitter. Do not retry 400, 401, 403, or cancellation.

- [ ] **Step 6: Add error-decoding tests**

Assert 401 maps to FeatureError.invalidAPIKey, 429 retries three times, 400 exposes the OpenAI message without headers, cancellation maps to CancellationError, and oversized files fail before URLSession runs.

- [ ] **Step 7: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/OpenAIClientTests -only-testing:WhisperTests/MultipartFormDataTests -only-testing:WhisperTests/RetryPolicyTests
~~~

Expected: deterministic pass with zero network calls.

- [ ] **Step 8: Commit**

~~~bash
git add Sources/OpenAI Tests/WhisperTests/OpenAI
git commit -m "feat(openai): add transcription and transform client" \
  -m $'- Implement REST requests for transcription and text transformation\n- Add multipart encoding, cancellation, and bounded retry behavior'
~~~

---

### Task 6: Microphone recorder and silence detection

**Files:**

- Create: Sources/Audio/MicrophoneRecorder.swift
- Create: Sources/Audio/AVAudioEngineRecorder.swift
- Create: Sources/Audio/AudioLevelMeter.swift
- Create: Sources/Audio/SilenceDetector.swift
- Test: Tests/WhisperTests/Audio/AudioLevelMeterTests.swift
- Test: Tests/WhisperTests/Audio/SilenceDetectorTests.swift

**Interfaces:**

- Produces: MicrophoneRecorder.start(deviceID:), levels AsyncStream<Float>, stop() returning CapturedAudio, cancel().
- Consumes: AppPaths temporary directory and AVFoundation.

- [ ] **Step 1: Define recorder contract**

~~~swift
struct CapturedAudio: Sendable {
    let fileURL: URL
    let duration: TimeInterval
    let peakLevel: Float
    let containsSpeech: Bool
}

protocol MicrophoneRecorder: Sendable {
    func start(deviceID: String?) async throws
    func levels() async -> AsyncStream<Float>
    func stop() async throws -> CapturedAudio
    func cancel() async
}
~~~

- [ ] **Step 2: Write meter and silence tests**

Generate Float samples in memory. Assert silence reports normalized level zero, a sine wave reports a stable positive level, and recordings shorter than 250 ms or below the speech threshold return containsSpeech false.

- [ ] **Step 3: Implement AVAudioEngine recording**

Install an input-node tap, convert buffers to mono 16 kHz PCM, and write a WAV file under Temporary. Publish smoothed RMS levels at no more than 30 updates per second. Stop removes the tap, closes the file, and calculates duration from frame count.

- [ ] **Step 4: Handle route and device errors**

Observe AVAudioEngineConfigurationChange. If the selected device disappears, finish the file and throw FeatureError.microphoneDisconnected on stop. cancel removes the temporary file.

- [ ] **Step 5: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/AudioLevelMeterTests -only-testing:WhisperTests/SilenceDetectorTests
~~~

Expected: tests pass without microphone permission.

- [ ] **Step 6: Commit**

~~~bash
git add Sources/Audio Tests/WhisperTests/Audio
git commit -m "feat(audio): capture push-to-talk microphone input" \
  -m $'- Record microphone input to temporary WAV files\n- Track audio levels and reject silent dictations before upload'
~~~

---

### Task 7: Mode transformation and dictation state machine

**Files:**

- Create: Sources/Dictation/ModePromptBuilder.swift
- Create: Sources/Dictation/DictationState.swift
- Create: Sources/Dictation/DictationCoordinator.swift
- Create: Sources/Accessibility/TextInsertionService.swift
- Test: Tests/WhisperTests/Dictation/ModePromptBuilderTests.swift
- Test: Tests/WhisperTests/Dictation/DictationCoordinatorTests.swift

**Interfaces:**

- Produces: ModePromptBuilder.instructions(for:), DictationState, DictationCoordinator.begin(), finish(), cancel(), and the TextInsertionService protocol consumed by the coordinator.
- Consumes: MicrophoneRecorder, OpenAIClient, ModeRepository, and HistoryRepository.

- [ ] **Step 1: Write exact prompt tests**

Assert Default instructions include preserve the spoken language, remove fillers, preserve technical terms, do not add facts, and output only final text. Assert a custom mode appends the user's instruction after fixed guardrails and never labels dictated text as a system instruction.

- [ ] **Step 2: Implement the state enum**

~~~swift
enum DictationState: Equatable, Sendable {
    case idle
    case recording(modeName: String)
    case transcribing
    case transforming
    case inserting
    case completed
    case failed(message: String, textOnClipboard: Bool)
}
~~~

Define the insertion boundary before implementing the coordinator:

~~~swift
protocol TextInsertionService: Sendable {
    func captureFocusedTarget() async throws -> FocusedTarget
    func insert(_ text: String, into target: FocusedTarget) async throws -> InsertionResult
}
~~~

Place FocusedTarget and InsertionResult beside this protocol so Task 8 can implement the boundary without changing the coordinator.

- [ ] **Step 3: Write coordinator transition tests**

With fakes, assert:

- begin moves idle to recording and snapshots the active mode;
- finish calls recorder stop, transcription, transformation, insertion, and history in order;
- silent input skips OpenAI and returns idle;
- cancel deletes temporary audio and stores no history;
- a second begin while busy is rejected;
- temporary audio is deleted after success but retained only when needed for retry.

- [ ] **Step 4: Implement coordinator**

Use an actor. Snapshot mode id, name, instructions, language hint, focused target, and start time at begin. Always store original and output text with the snapshot. Emit state changes through AsyncStream<DictationState>.

- [ ] **Step 5: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/ModePromptBuilderTests -only-testing:WhisperTests/DictationCoordinatorTests
~~~

Expected: all transition and cleanup tests pass.

- [ ] **Step 6: Commit**

~~~bash
git add Sources/Dictation Tests/WhisperTests/Dictation
git commit -m "feat(dictation): process speech through active modes" \
  -m $'- Orchestrate transcription, mode prompts, insertion, and history\n- Define cancellable dictation states and insertion boundaries'
~~~

---

### Task 8: Focus capture and reliable text insertion

**Files:**

- Create: Sources/Accessibility/FocusedTarget.swift
- Create: Sources/Accessibility/AXTextInsertionService.swift
- Create: Sources/Accessibility/PasteboardRestorer.swift
- Test: Tests/WhisperTests/Accessibility/TextInsertionServiceTests.swift

**Interfaces:**

- Produces: AXTextInsertionService implementing the TextInsertionService boundary from Task 7.
- Consumes: FocusedTarget, InsertionResult, Accessibility permission, and CGEvent posting.

- [ ] **Step 1: Define target and result**

~~~swift
struct FocusedTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let element: AXUIElement?
}

enum InsertionResult: Equatable, Sendable {
    case insertedDirectly
    case pasted
    case copiedForManualPaste
}
~~~

- [ ] **Step 2: Write strategy tests**

Use fake AX and pasteboard adapters. Assert direct selected-text insertion is preferred, unsupported AX attributes fall back to paste, the original pasteboard is restored after successful paste, and failed paste leaves final text on the clipboard.

- [ ] **Step 3: Implement focused-target capture**

Capture NSWorkspace.shared.frontmostApplication before any Whisper panel appears. Query the system-wide focused element through AXUIElementCreateSystemWide and kAXFocusedUIElementAttribute.

- [ ] **Step 4: Implement insertion strategies**

Try kAXSelectedTextAttribute first. If unsupported, activate the stored application, place text on NSPasteboard, post Command-V key down and up with CGEvent, wait 150 ms, then restore the prior pasteboard only when the paste event was sent successfully. Never restore on copiedForManualPaste.

- [ ] **Step 5: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/TextInsertionServiceTests
~~~

Expected: all insertion-strategy tests pass.

- [ ] **Step 6: Commit**

~~~bash
git add Sources/Accessibility Tests/WhisperTests/Accessibility
git commit -m "feat(accessibility): insert dictation into focused apps" \
  -m $'- Capture the focused target before showing Whisper UI\n- Insert through Accessibility with a clipboard fallback and restoration'
~~~

---

### Task 9: Global shortcuts and shortcut recorder

**Files:**

- Create: Sources/Hotkeys/HotkeyEvent.swift
- Create: Sources/Hotkeys/HotkeyStateMachine.swift
- Create: Sources/Hotkeys/GlobalHotkeyMonitor.swift
- Create: Sources/Hotkeys/CGEventHotkeyMonitor.swift
- Create: Sources/Hotkeys/ShortcutConflictDetector.swift
- Test: Tests/WhisperTests/Hotkeys/HotkeyStateMachineTests.swift

**Interfaces:**

- Produces: AsyncStream<HotkeyActionEvent>, begin shortcut capture, conflict validation.
- Consumes: Shortcut values from Task 2 and Accessibility permission.

- [ ] **Step 1: Write modifier transition tests**

~~~swift
func testRightOptionProducesPressThenRelease() {
    var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
    XCTAssertEqual(machine.consume(.flagsChanged(keyCode: 61, flags: [.option])), .pressed(.pushToTalk))
    XCTAssertEqual(machine.consume(.flagsChanged(keyCode: 61, flags: [])), .released(.pushToTalk))
}

func testLeftOptionDoesNotTriggerRightOptionShortcut() {
    var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
    XCTAssertNil(machine.consume(.flagsChanged(keyCode: 58, flags: [.option])))
}
~~~

- [ ] **Step 2: Implement the pure state machine**

Handle keyDown, keyUp, and flagsChanged. Suppress auto-repeat. Emit pressed and released only once per physical transition. Command-Shift-K and Command-Shift-R emit invoked events on keyDown. Escape emits invoked cancel only while a feature is active.

- [ ] **Step 3: Implement CGEventTap monitor**

Create a session event tap for keyDown, keyUp, and flagsChanged. Put the C callback on a dedicated run-loop thread and immediately dispatch normalized HotkeyEvent values to the monitor actor. Re-enable taps disabled by timeout or user input.

- [ ] **Step 4: Implement shortcut recording and conflict checks**

Capture one modifier-only key or a standard key combination. Reject duplicates, Command-Q, Command-W, Command-H, Command-M, and unmodified printable keys. Provide reset to defaults.

- [ ] **Step 5: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/HotkeyStateMachineTests
~~~

Expected: transition, repeat, conflict, and reset tests pass.

- [ ] **Step 6: Commit**

~~~bash
git add Sources/Hotkeys Tests/WhisperTests/Hotkeys
git commit -m "feat(hotkeys): add global push-to-talk controls" \
  -m $'- Register push-to-talk and global action shortcuts\n- Add conflict validation and shortcut recording state'
~~~

---

### Task 10: HUD, mode switcher, and menu-bar shell

**Files:**

- Create: Sources/UI/HUD/DictationHUDController.swift
- Create: Sources/UI/HUD/DictationHUDView.swift
- Create: Sources/UI/ModeSwitcher/ModeSwitcherController.swift
- Create: Sources/UI/ModeSwitcher/ModeSwitcherView.swift
- Create: Sources/UI/MenuBar/MenuBarContentView.swift
- Modify: Sources/WhisperApp/AppDelegate.swift
- Test: Tests/WhisperTests/UI/ModeSwitcherModelTests.swift

**Interfaces:**

- Produces: DictationHUDController.render(state:level:), ModeSwitcherController.show(), MenuBarContentView.
- Consumes: DictationState, ModeRepository, GlobalHotkeyMonitor.

- [ ] **Step 1: Write mode-switcher model tests**

Assert search is case-insensitive, arrow navigation wraps, Return activates the selected mode, Escape closes without changes, and disabled modes are excluded.

- [ ] **Step 2: Implement nonactivating dictation HUD**

Use NSPanel with nonactivatingPanel style, clear background, statusBar window level, collection behavior canJoinAllSpaces and fullScreenAuxiliary. Place it bottom-center on the screen containing the captured target app. States are listening, transcribing, processing, inserted, cancelled, and error. The panel never becomes key.

- [ ] **Step 3: Implement mode switcher panel**

Use NSPanel that can become key. Save the prior NSRunningApplication, focus the search field, and restore the application on close. Render mode name, active checkmark, optional language hint, and keyboard footer.

- [ ] **Step 4: Implement menu-bar content**

Use NSStatusItem through AppDelegate so the icon can reflect ready, dictating, recording meeting, processing, and error. The popover exposes current mode, start dictation, change mode, record meeting, recent history, open main window, and quit.

- [ ] **Step 5: Wire hotkeys to controllers**

Right Option pressed calls DictationCoordinator.begin; released calls finish. Command-Shift-K opens the switcher. Escape cancels dictation or closes the top panel. Leave meeting action wired to a stub closure until Task 12.

- [ ] **Step 6: Run tests and launch**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/ModeSwitcherModelTests
open build/DerivedData/Build/Products/Debug/Whisper.app
~~~

Expected: tests pass; the menu-bar icon and panels render without a Dock icon.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/UI Sources/WhisperApp/AppDelegate.swift Tests/WhisperTests/UI
git commit -m "feat(ui): add dictation HUD and mode switcher" \
  -m $'- Add nonactivating dictation feedback and error states\n- Add keyboard-first mode switching and menu-bar controls'
~~~

---

### Task 11: Onboarding, Home, Modes, and Settings screens

**Files:**

- Create: Sources/UI/AppRootView.swift
- Create: Sources/UI/SidebarDestination.swift
- Create: Sources/UI/Onboarding/OnboardingView.swift
- Create: Sources/UI/Home/HomeView.swift
- Create: Sources/UI/Modes/ModesListView.swift
- Create: Sources/UI/Modes/ModeEditorView.swift
- Create: Sources/UI/Settings/SettingsView.swift
- Create: Sources/UI/Components/SettingsCard.swift
- Create: Sources/UI/Components/PermissionRow.swift
- Create: Sources/UI/Components/ShortcutRecorderView.swift
- Create: Tests/WhisperUITests/OnboardingUITests.swift
- Create: Tests/WhisperUITests/ModesUITests.swift

**Interfaces:**

- Produces: navigable main window and the first-run setup flow.
- Consumes: repositories, SecureStore, PermissionService, AppSettings, DesignTokens.

- [ ] **Step 1: Add UI launch arguments**

Support UI-test arguments:

- --ui-testing;
- --onboarding-incomplete;
- --permissions-granted;
- --api-key-state valid or invalid.

Inject in-memory persistence and fake services only when --ui-testing is present.

- [ ] **Step 2: Write onboarding UI test**

Launch incomplete onboarding, enter a fake key, tap Test, advance through the three permission pages, and assert the Ready page shows Right Option, Command-Shift-K, and Command-Shift-R.

- [ ] **Step 3: Implement root navigation**

Use NavigationSplitView with a 248-point sidebar and destinations Home, Modes, Recordings, History, Settings. Window minimum size is 1120 by 760 and ideal size is 1320 by 860.

- [ ] **Step 4: Implement onboarding**

Each step shows explanation, live state, a single primary action, Back, and Continue. Do not show a fake granted state. If Screen Recording requires relaunch, show Relaunch Whisper after permission changes.

- [ ] **Step 5: Implement Home**

Show active mode, microphone, OpenAI status, permissions, shortcuts, and five latest history items. Buttons call the same coordinators used by hotkeys.

- [ ] **Step 6: Implement Modes**

Create, duplicate, activate, and delete custom modes. Default row hides delete and rename. ModeEditorView validates live, disables Save until changed and valid, and confirms destructive deletion.

- [ ] **Step 7: Implement Settings**

API key controls never reveal the full saved value. Shortcut rows use ShortcutRecorderView. Permission rows open the correct System Settings privacy pane. Launch at Login and sound effects update AppSettings immediately.

- [ ] **Step 8: Run UI tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperUITests/OnboardingUITests -only-testing:WhisperUITests/ModesUITests
~~~

Expected: onboarding and mode creation pass.

- [ ] **Step 9: Commit**

~~~bash
git add Sources/UI Tests/WhisperUITests
git commit -m "feat(ui): build onboarding modes and settings" \
  -m $'- Build onboarding, Home, Modes, Recordings, History, and Settings shells\n- Apply the baseline native macOS design tokens and validation states'
~~~

---

### Task 12: ScreenCaptureKit meeting recorder

**Files:**

- Create: Sources/Audio/MeetingRecorder.swift
- Create: Sources/Audio/ScreenCaptureMeetingRecorder.swift
- Create: Sources/Audio/SampleBufferAudioWriter.swift
- Create: Sources/Audio/DiskSpaceMonitor.swift
- Test: Tests/WhisperTests/Audio/DiskSpaceMonitorTests.swift
- Test: Tests/WhisperTests/Audio/SampleBufferAudioWriterTests.swift

**Interfaces:**

- Produces: MeetingRecorder.start(configuration:), levels(), stop() returning CapturedMeeting, interrupt(reason:).
- Consumes: ScreenCaptureKit, AVFoundation, AppPaths, selected microphone id.

- [ ] **Step 1: Define meeting capture contract**

~~~swift
struct MeetingCaptureConfiguration: Sendable {
    let meetingID: UUID
    let microphoneDeviceID: String?
    let maximumDuration: TimeInterval
}

struct CapturedMeeting: Sendable {
    let microphoneURL: URL
    let systemAudioURL: URL
    let startedAt: Date
    let endedAt: Date
}

protocol MeetingRecorder: Sendable {
    func start(configuration: MeetingCaptureConfiguration) async throws
    func levels() async -> AsyncStream<MeetingAudioLevels>
    func stop() async throws -> CapturedMeeting
}
~~~

- [ ] **Step 2: Write disk-space tests**

Inject URL resource values. Assert recording is blocked below 2 GB, allowed at 2 GB or more, and warning state appears below 4 GB.

- [ ] **Step 3: Implement sample-buffer writer**

Create one AVAssetWriter per track with file type M4A, AAC-LC, mono, 44.1 kHz, and 64 kbps. Retimestamp sample buffers relative to the first PTS before append. finish waits for writer completion and verifies the file exists and is nonempty.

- [ ] **Step 4: Implement ScreenCaptureKit capture**

Use SCShareableContent to select the main display and SCContentFilter for that display. Configure capturesAudio true, captureMicrophone true, excludesCurrentProcessAudio true, and microphoneCaptureDeviceID when provided. Add only audio and microphone stream outputs. Route each output type to its writer on a dedicated serial queue.

- [ ] **Step 5: Implement lifecycle safeguards**

Reject a second start, enforce three hours with a timer, finalize both writers on stream error, and return a partial-track error that names the missing source. Return CapturedMeeting only after both writers finish; Task 14 persists the transition from recording to captured.

- [ ] **Step 6: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/DiskSpaceMonitorTests -only-testing:WhisperTests/SampleBufferAudioWriterTests
~~~

Expected: writer tests use generated CMSampleBuffer fixtures and produce playable M4A metadata.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/Audio Tests/WhisperTests/Audio
git commit -m "feat(recordings): capture Mac and microphone audio" \
  -m $'- Capture ScreenCaptureKit system and microphone outputs separately\n- Persist recoverable recording sessions and enforce the duration limit'
~~~

---

### Task 13: Long-audio chunks and chronological transcript merge

**Files:**

- Create: Sources/Meetings/AudioChunkPlanner.swift
- Create: Sources/Meetings/AVAssetChunkExporter.swift
- Create: Sources/Meetings/TranscriptMerger.swift
- Create: Sources/Meetings/MeetingTranscriber.swift
- Test: Tests/WhisperTests/Meetings/AudioChunkPlannerTests.swift
- Test: Tests/WhisperTests/Meetings/TranscriptMergerTests.swift

**Interfaces:**

- Produces: plan(duration:chunkDuration:overlap:), export(track:plan:), transcribe(meeting:), merge(_:).
- Consumes: CapturedMeeting, OpenAIClient.transcribeDiarized, HistoryRepository.

- [ ] **Step 1: Write exact chunk-plan tests**

~~~swift
func testThreeHoursProducesNineTwentyMinuteChunks() {
    let chunks = AudioChunkPlanner.plan(duration: 10_800, chunkDuration: 1_200, overlap: 1)
    XCTAssertEqual(chunks.count, 9)
    XCTAssertEqual(chunks.first?.start, 0)
    XCTAssertEqual(chunks.last?.end, 10_800)
    XCTAssertEqual(chunks[1].start, 1_199)
}
~~~

The planner uses nominal 20-minute boundaries. Chunk zero starts at 0. Every later chunk starts one second before its nominal boundary, while its end remains on the next nominal boundary. This creates nine chunks for three hours and a one-second overlap without shortening forward progress.

- [ ] **Step 2: Implement chunk export**

Use AVAssetExportSession with an M4A-compatible preset and CMTimeRange for each planned chunk. Store chunk metadata with source, index, start offset, end offset, URL, status, and retry count. Verify each file is at most 20 MB; if larger, split that range in half recursively.

- [ ] **Step 3: Write merge tests**

Use overlapping fixtures:

~~~swift
let input = [
    TranscriptSegment(source: .you, startTime: 0, endTime: 4, text: "Let's begin."),
    TranscriptSegment(source: .others, startTime: 3, endTime: 8, text: "Sure, let's begin."),
    TranscriptSegment(source: .you, startTime: 1199, endTime: 1202, text: "Next topic."),
    TranscriptSegment(source: .you, startTime: 1200, endTime: 1203, text: "Next topic.")
]
~~~

Assert the duplicate Next topic appears once, output sorts by start time, and adjacent same-source segments separated by less than five seconds coalesce.

- [ ] **Step 4: Implement transcript normalization**

For every API segment, add the chunk start offset. Ignore the model speaker identity and map microphone chunks to You and system chunks to Others. Normalize whitespace. Deduplicate segments when normalized text matches and time ranges overlap by at least 50 percent.

- [ ] **Step 5: Implement MeetingTranscriber**

Process chunks with at most two concurrent requests. Persist every completed chunk result before starting the next batch. Update progressCompleted and progressTotal. Carry the final 200 characters of a prior chunk only in local merge context; do not pass custom prompts to the diarization model.

- [ ] **Step 6: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/AudioChunkPlannerTests -only-testing:WhisperTests/TranscriptMergerTests
~~~

Expected: chunk coverage, size fallback, ordering, deduplication, and coalescing tests pass.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/Meetings Tests/WhisperTests/Meetings
git commit -m "feat(recordings): transcribe long calls in resumable chunks" \
  -m $'- Export bounded overlapping audio chunks for transcription\n- Merge timestamped You and Others segments without overlap duplicates'
~~~

---

### Task 14: Meeting processing, recovery, and recording UI

**Files:**

- Create: Sources/Meetings/MeetingProcessingCoordinator.swift
- Create: Sources/Meetings/MeetingRecoveryService.swift
- Create: Sources/UI/Recordings/RecordingsView.swift
- Create: Sources/UI/Recordings/RecordingHUDController.swift
- Create: Sources/UI/Recordings/RecordingHUDView.swift
- Modify: Sources/UI/MenuBar/MenuBarContentView.swift
- Modify: Sources/WhisperApp/AppDelegate.swift
- Test: Tests/WhisperTests/Meetings/MeetingProcessingCoordinatorTests.swift
- Create: Tests/WhisperUITests/RecordingsUITests.swift

**Interfaces:**

- Produces: toggleRecording(), retry(meetingID:), reprocess(meetingID:instructions:), resumeIncompleteJobs().
- Consumes: MeetingRecorder, MeetingTranscriber, OpenAI transform, HistoryRepository, settings recording instructions.

- [ ] **Step 1: Write coordinator recovery tests**

Assert:

- start creates a recording row and snapshots instructions;
- stop transitions recording to captured before network work;
- captured resumes at transcribing after relaunch;
- transcribing skips chunks already persisted;
- processing retries only the Responses request;
- invalid API key leaves audio and transcript intact;
- push-to-talk is rejected while a meeting is recording.

- [ ] **Step 2: Implement durable coordinator**

Use an actor. State transitions must be persisted before external work begins. On capture completion, launch transcription in a child Task. On success, format the transcript as timestamped You/Others text and call transform with the saved instruction. Store processedText and mark ready.

- [ ] **Step 3: Implement startup recovery**

At launch query incompleteMeetings. Convert recording or finalizing rows left by a crash to failed with an interrupted-capture message. Resume captured, transcribing, and processing rows when the API key exists and network becomes available.

- [ ] **Step 4: Implement Recordings screen**

Render microphone and system source states, selected microphone, Command-Shift-R shortcut, three-hour limit, large instruction editor, Auto result language, Start or Stop, and privacy text. Show live timer and both meters while active.

- [ ] **Step 5: Implement recording HUD and menu-bar states**

HUD shows timer, microphone meter, system meter, and Stop. It does not steal focus. Menu bar shows a recording indicator and timer. Command-Shift-R toggles the coordinator.

- [ ] **Step 6: Write UI test**

With a fake recorder, start recording, advance fake time to 00:37:18, stop, assert Finalizing then Transcribing 1 of 2, resolve fake calls, and assert Ready.

- [ ] **Step 7: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/MeetingProcessingCoordinatorTests -only-testing:WhisperUITests/RecordingsUITests
~~~

Expected: recovery and UI state tests pass without Screen Recording permission.

- [ ] **Step 8: Commit**

~~~bash
git add Sources/Meetings Sources/UI/Recordings Sources/UI/MenuBar Sources/WhisperApp/AppDelegate.swift Tests
git commit -m "feat(recordings): process and recover meeting captures" \
  -m $'- Add durable transcription and processing job recovery\n- Build recording progress, detail, retry, and reprocess flows'
~~~

---

### Task 15: Unified History and audio cleanup

**Files:**

- Create: Sources/UI/History/HistoryView.swift
- Create: Sources/UI/History/HistorySearchModel.swift
- Create: Sources/UI/History/DictationDetailView.swift
- Create: Sources/UI/History/MeetingDetailView.swift
- Create: Sources/UI/History/TranscriptView.swift
- Create: Sources/Audio/AudioPlaybackService.swift
- Create: Sources/Persistence/RetentionService.swift
- Test: Tests/WhisperTests/UI/HistorySearchModelTests.swift
- Test: Tests/WhisperTests/Persistence/RetentionServiceTests.swift
- Create: Tests/WhisperUITests/HistoryUITests.swift

**Interfaces:**

- Produces: searchable unified history, details, copy, export, reprocess, retry, playback, and delete.
- Consumes: HistoryRepository, MeetingProcessingCoordinator, FileManager, AVPlayer.

- [ ] **Step 1: Write history filtering tests**

Use dictation and meeting fixtures across Today and Yesterday. Assert All, Dictations, Recordings, case-insensitive search across title and text, newest-first sorting, and stable date groups.

- [ ] **Step 2: Implement history list**

Rows show type, mode or duration, timestamp, status, and preview. Empty state changes with active filter or search. Failed recordings show Retry without hiding the error.

- [ ] **Step 3: Implement details**

Dictation detail shows original, output, mode snapshot, target app, copy, and delete. Meeting detail shows editable title, player, transcript/result tabs, You/Others timestamps, saved instructions, progress, Retry, Reprocess, Export Text, and Delete.

- [ ] **Step 4: Implement playback**

AudioPlaybackService can play either track or a temporary mixed composition. Keep the originals unchanged. Stop playback when the detail view closes or the item is deleted.

- [ ] **Step 5: Implement retention and deletion**

Forever does no automatic deletion. Manual meeting delete confirms, deletes the SwiftData row in a transaction, then removes only its meeting directory. If file deletion fails, persist a cleanup-required marker and retry on next launch.

- [ ] **Step 6: Run tests**

Run:

~~~bash
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test -only-testing:WhisperTests/HistorySearchModelTests -only-testing:WhisperTests/RetentionServiceTests -only-testing:WhisperUITests/HistoryUITests
~~~

Expected: filters, details, cleanup retry, and delete confirmation pass.

- [ ] **Step 7: Commit**

~~~bash
git add Sources/UI/History Sources/Audio/AudioPlaybackService.swift Sources/Persistence/RetentionService.swift Tests
git commit -m "feat(history): browse dictations and call transcripts" \
  -m $'- Add unified search, filters, detail views, and exports\n- Delete metadata and owned audio safely through retention services'
~~~

---

### Task 16: Packaging, diagnostics, and end-to-end acceptance

**Files:**

- Create: scripts/package-local.sh
- Create: scripts/install-local.sh
- Create: scripts/create-synthetic-call.swift
- Create: README.md
- Create: docs/testing/manual-acceptance.md
- Create: Tests/WhisperTests/Security/RedactionTests.swift
- Modify: Sources/WhisperApp/AppDelegate.swift

**Interfaces:**

- Produces: build/Whisper.app, local installation instructions, synthetic long-audio fixture, and final acceptance evidence.
- Consumes: all prior tasks.

- [ ] **Step 1: Add secret-redaction tests**

Create an API key fixture beginning sk-test and pass invalid-key and server-error responses through every error formatter. Assert the key, Authorization, dictated text fixture, and instruction fixture never appear in localizedDescription or debugDescription.

- [ ] **Step 2: Implement local packaging**

scripts/package-local.sh must:

1. run xcodegen generate;
2. run all unit and UI tests;
3. build Release into build/DerivedData;
4. copy Whisper.app to build/Whisper.app;
5. ad-hoc sign with codesign --force --deep --sign -;
6. verify with codesign --verify --deep --strict;
7. print the final path.

scripts/install-local.sh copies the verified bundle to /Applications/Whisper.app only when the exact source bundle exists and the bundle identifier is dev.yury.whisper. If the destination exists, the script stops unless the user supplies --replace; replacement first moves the existing dev.yury.whisper bundle to /Applications/Whisper.previous.app and never deletes unrelated paths.

- [ ] **Step 3: Add first-launch guidance**

README explains:

- prerequisites and bootstrap;
- how to build and install;
- right-click Open when Gatekeeper warns;
- Microphone, Screen Recording, and Accessibility setup;
- where the API key is stored;
- where recordings live;
- how to remove the app and its local data manually;
- current privacy boundaries and OpenAI usage.

- [ ] **Step 4: Create acceptance checklist**

docs/testing/manual-acceptance.md contains explicit checks for:

- Default Russian and English dictation;
- English Translation custom mode;
- Right Option hold and Escape cancel;
- Command-Shift-K switcher;
- insertion in TextEdit, Notes, Safari, Slack, and VS Code;
- missing Accessibility clipboard fallback;
- invalid key, offline, 429, and server error;
- system audio plus microphone capture;
- Command-Shift-R toggle and timer;
- processing retry after relaunch;
- transcript ordering You/Others;
- result reprocessing;
- delete and playback;
- low disk space;
- first-launch permissions.

- [ ] **Step 5: Add three-hour synthetic test helper**

scripts/create-synthetic-call.swift generates two low-bitrate three-hour M4A tracks with alternating tones and short spoken fixture clips at known timestamps. The test validates disk growth, chunk count of nine per track before size fallback, and no process memory growth proportional to duration.

- [ ] **Step 6: Run complete verification**

Run:

~~~bash
xcodegen generate
xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" test
./scripts/package-local.sh
codesign --verify --deep --strict build/Whisper.app
spctl --assess --type execute build/Whisper.app || test $? -eq 3
~~~

Expected:

- all automated tests pass;
- BUILD SUCCEEDED;
- codesign verification succeeds;
- spctl may reject the ad-hoc app as unnotarized, which is expected for this personal MVP.

- [ ] **Step 7: Perform manual acceptance**

Run every row in docs/testing/manual-acceptance.md on the target Mac. Record macOS version, app commit, result, and notes. Do not paste a real API key into logs or the checklist.

- [ ] **Step 8: Commit**

~~~bash
git add scripts README.md docs/testing Tests/WhisperTests/Security Sources/WhisperApp/AppDelegate.swift
git commit -m "chore(macos): package and verify personal MVP" \
  -m $'- Add recoverable local installation and diagnostics scripts\n- Document and execute automated and manual acceptance checks'
~~~

---

## Implementation order and review gates

Tasks 1 through 5 establish the platform, data, security, and API boundary. Review this foundation before adding audio.

Tasks 6 through 11 produce the complete push-to-talk experience. At this gate, Default and custom modes must work end to end in TextEdit before meeting recording begins.

Tasks 12 through 15 add durable call recording, processing, and history. At this gate, a 10-minute real call and a synthetic three-hour call must both complete without data loss.

Task 16 packages the personal MVP and verifies the first-run experience.

Do not combine review gates. Audio capture, Accessibility insertion, and destructive history cleanup require independent review because each has different failure and privacy risks.

## Final acceptance definition

The MVP is complete only when:

- Right Option dictation succeeds in the five target apps;
- active mode switching works without losing the previous app focus;
- custom instructions reliably transform rather than answer dictated text;
- a call captures both separate tracks and survives network failure;
- History displays a chronological You/Others transcript and processed result;
- retry and reprocess do not require re-recording;
- the real API key is present only in Keychain;
- all automated tests and the manual acceptance checklist pass;
- build/Whisper.app launches through the documented personal-install flow.
