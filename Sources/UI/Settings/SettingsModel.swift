import AVFoundation
import Foundation
import Observation

struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

@MainActor
protocol MicrophoneDeviceProviding {
    func availableMicrophones() -> [MicrophoneDevice]
}

@MainActor
struct SystemMicrophoneDeviceProvider: MicrophoneDeviceProviding {
    func availableMicrophones() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum APIKeySettingsState: Equatable, Sendable {
    case missing
    case saved
    case testing
    case connected
    case failed
}

enum SettingsValidationError: LocalizedError, Equatable {
    case blankAPIKey

    var errorDescription: String? {
        "Enter an OpenAI API key before saving."
    }
}

@MainActor
@Observable
final class SettingsModel {
    private let secureStore: any SecureStore
    private let settingsStore: AppSettingsStore
    private let permissionService: PermissionService
    private let launchAtLoginService: LaunchAtLoginService
    private let microphoneProvider: any MicrophoneDeviceProviding
    private let testConnection: @MainActor () async throws -> Void
    private let beginCapture: @MainActor (ShortcutAction) -> Void
    private let shortcutsChanged: @MainActor ([ShortcutAction: Shortcut]) -> Void

    var apiKeyInput = ""
    private(set) var apiKeyState: APIKeySettingsState
    private(set) var isReplacingAPIKey = false
    private(set) var microphones: [MicrophoneDevice]
    private(set) var selectedMicrophoneID: String?
    private(set) var shortcuts: [ShortcutAction: Shortcut]
    private(set) var capturingShortcut: ShortcutAction?
    private(set) var shortcutError: String?
    private(set) var launchAtLoginState: LaunchAtLoginState
    private(set) var soundEffects: Bool
    private(set) var retention: RetentionPolicy
    private(set) var permissions: PermissionSnapshot
    private(set) var apiKeyErrorMessage: String?
    private(set) var launchAtLoginErrorMessage: String?
    private var apiKeyGeneration = 0

    init(
        secureStore: any SecureStore,
        settingsStore: AppSettingsStore,
        permissionService: PermissionService,
        launchAtLoginService: LaunchAtLoginService,
        microphoneProvider: any MicrophoneDeviceProviding = SystemMicrophoneDeviceProvider(),
        testConnection: @escaping @MainActor () async throws -> Void,
        beginShortcutCapture: @escaping @MainActor (ShortcutAction) -> Void = { _ in },
        shortcutsChanged: @escaping @MainActor ([ShortcutAction: Shortcut]) -> Void = { _ in }
    ) {
        self.secureStore = secureStore
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.launchAtLoginService = launchAtLoginService
        self.microphoneProvider = microphoneProvider
        self.testConnection = testConnection
        beginCapture = beginShortcutCapture
        self.shortcutsChanged = shortcutsChanged
        do {
            apiKeyState = try secureStore.readOpenAIKey()?.isEmpty == false ? .saved : .missing
            apiKeyErrorMessage = nil
        } catch {
            apiKeyState = .missing
            apiKeyErrorMessage = Self.keychainReadError
        }
        launchAtLoginErrorMessage = nil
        microphones = microphoneProvider.availableMicrophones()
        selectedMicrophoneID = settingsStore.selectedMicrophoneID
        shortcuts = settingsStore.shortcuts
        launchAtLoginState = launchAtLoginService.state
        soundEffects = settingsStore.soundEffects
        retention = settingsStore.retention
        permissions = permissionService.snapshot()
    }

    var apiKeyStatusLabel: String {
        switch apiKeyState {
        case .missing: "Not configured"
        case .saved: "Saved in Keychain"
        case .testing: "Testing connection…"
        case .connected: "Connected"
        case .failed: "Connection could not be verified. Check your key and network, then try again."
        }
    }

    var errorMessage: String? {
        apiKeyErrorMessage ?? launchAtLoginErrorMessage
    }

    var selectedMicrophoneName: String {
        guard let selectedMicrophoneID else { return "System Default" }
        return microphones.first(where: { $0.id == selectedMicrophoneID })?.name ?? "Unavailable microphone"
    }

    func refresh() {
        refreshAPIKeyState()
        microphones = microphoneProvider.availableMicrophones()
        selectedMicrophoneID = settingsStore.selectedMicrophoneID
        shortcuts = settingsStore.shortcuts
        launchAtLoginState = launchAtLoginService.state
        soundEffects = settingsStore.soundEffects
        retention = settingsStore.retention
        permissions = permissionService.snapshot()
    }

    func saveAPIKey() throws {
        let value = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SettingsValidationError.blankAPIKey }
        try secureStore.saveOpenAIKey(value)
        apiKeyGeneration += 1
        apiKeyInput = ""
        apiKeyState = .saved
        isReplacingAPIKey = false
        apiKeyErrorMessage = nil
    }

    func saveAPIKeyForPresentation() {
        do {
            try saveAPIKey()
        } catch SettingsValidationError.blankAPIKey {
            apiKeyErrorMessage = SettingsValidationError.blankAPIKey.localizedDescription
        } catch {
            apiKeyErrorMessage = "The API key could not be saved to Keychain."
        }
    }

    func beginAPIKeyReplacement() {
        apiKeyGeneration += 1
        apiKeyInput = ""
        isReplacingAPIKey = true
        apiKeyErrorMessage = nil
    }

    func cancelAPIKeyReplacement() {
        apiKeyGeneration += 1
        apiKeyInput = ""
        isReplacingAPIKey = false
        apiKeyErrorMessage = nil
    }

    func removeAPIKey() throws {
        try secureStore.deleteOpenAIKey()
        apiKeyGeneration += 1
        apiKeyInput = ""
        apiKeyState = .missing
        isReplacingAPIKey = false
        apiKeyErrorMessage = nil
    }

    func removeAPIKeyForPresentation() {
        do {
            try removeAPIKey()
        } catch {
            apiKeyErrorMessage = "The API key could not be removed from Keychain."
        }
    }

    func testAPIConnection() async {
        guard apiKeyState != .testing, !isReplacingAPIKey else { return }
        let generation = apiKeyGeneration
        apiKeyState = .testing
        do {
            try await testConnection()
            guard generation == apiKeyGeneration, apiKeyState == .testing else { return }
            apiKeyState = .connected
        } catch {
            guard generation == apiKeyGeneration, apiKeyState == .testing else { return }
            apiKeyState = .failed
        }
    }

    func selectMicrophone(_ id: String?) {
        selectedMicrophoneID = id
        settingsStore.selectedMicrophoneID = id
    }

    func setSoundEffects(_ enabled: Bool) {
        soundEffects = enabled
        settingsStore.soundEffects = enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
        }
        launchAtLoginState = launchAtLoginService.state
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openLoginItemsSettings()
    }

    func openPermissionSettings(_ kind: PermissionKind) {
        permissionService.openSettings(for: kind)
    }

    func beginShortcutCapture(_ action: ShortcutAction) {
        capturingShortcut = action
        shortcutError = nil
        beginCapture(action)
    }

    func cancelShortcutCapture() {
        capturingShortcut = nil
        shortcutError = nil
    }

    func acceptCapturedShortcut(_ captured: CapturedShortcut) {
        guard capturingShortcut == captured.action else { return }
        capturingShortcut = nil
        if let conflict = ShortcutConflictDetector.conflict(
            for: captured.shortcut,
            action: captured.action,
            existing: shortcuts
        ) {
            shortcutError = Self.message(for: conflict)
            return
        }
        shortcuts[captured.action] = captured.shortcut
        settingsStore.shortcuts = shortcuts
        shortcutError = nil
        shortcutsChanged(shortcuts)
    }

    func resetShortcut(_ action: ShortcutAction) {
        guard let value = AppSettings.defaults.shortcuts[action] else { return }
        shortcuts[action] = value
        settingsStore.shortcuts = shortcuts
        shortcutError = nil
        shortcutsChanged(shortcuts)
    }

    private static func message(for conflict: ShortcutConflict) -> String {
        switch conflict {
        case let .duplicate(action):
            "That shortcut is already used by \(action.title)."
        case .systemReserved:
            "That shortcut is reserved by macOS."
        case .unmodifiedPrintable:
            "Add a modifier key to printable shortcuts."
        }
    }

    private func refreshAPIKeyState() {
        guard apiKeyState != .testing else { return }
        do {
            let hasSavedKey = try secureStore.readOpenAIKey()?.isEmpty == false
            if hasSavedKey {
                if apiKeyState != .connected { apiKeyState = .saved }
            } else {
                apiKeyState = .missing
            }
            if apiKeyErrorMessage == Self.keychainReadError {
                apiKeyErrorMessage = nil
            }
        } catch {
            apiKeyErrorMessage = Self.keychainReadError
        }
    }

    private static let keychainReadError = "The API key status could not be read from Keychain."
}

extension ShortcutAction {
    var title: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .changeMode: "Change Mode"
        case .recordMeeting: "Record Meeting"
        case .cancel: "Cancel"
        }
    }
}
