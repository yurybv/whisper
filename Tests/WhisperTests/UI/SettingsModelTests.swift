import XCTest
@testable import Whisper

@MainActor
final class SettingsModelTests: XCTestCase {
    func testSettingsStorePersistsDeviceShortcutsAndSoundImmediately() throws {
        let defaults = try makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        var shortcuts = store.shortcuts
        shortcuts[.changeMode] = Shortcut(key: .k, modifiers: [.control, .command])

        store.selectedMicrophoneID = "usb-mic"
        store.shortcuts = shortcuts
        store.soundEffects = false

        let reopened = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.selectedMicrophoneID, "usb-mic")
        XCTAssertEqual(reopened.shortcuts, shortcuts)
        XCTAssertFalse(reopened.soundEffects)
        XCTAssertEqual(reopened.retention, .forever)
    }

    func testPartiallyStoredShortcutsMergeWithApprovedDefaults() throws {
        let defaults = try makeDefaults()
        let replacement = Shortcut(key: .k, modifiers: [.control, .command])
        defaults.set(
            try JSONEncoder().encode([ShortcutAction.changeMode: replacement]),
            forKey: "shortcuts"
        )

        let shortcuts = AppSettingsStore(defaults: defaults).shortcuts

        XCTAssertEqual(shortcuts[.changeMode], replacement)
        XCTAssertEqual(shortcuts[.pushToTalk], AppSettings.defaults.shortcuts[.pushToTalk])
        XCTAssertEqual(shortcuts[.recordMeeting], AppSettings.defaults.shortcuts[.recordMeeting])
        XCTAssertEqual(shortcuts[.cancel], AppSettings.defaults.shortcuts[.cancel])
    }

    func testSavedAPIKeyIsRepresentedWithoutRevealingItsValue() throws {
        let secureStore = InMemorySecureStore()
        secureStore.saveOpenAIKey("sk-test-private-settings-key")
        let model = try makeModel(secureStore: secureStore)

        XCTAssertEqual(model.apiKeyState, .saved)
        XCTAssertEqual(model.apiKeyInput, "")
        XCTAssertFalse(String(describing: model.apiKeyState).contains("sk-test-private-settings-key"))

        try model.removeAPIKey()

        XCTAssertEqual(model.apiKeyState, .missing)
        XCTAssertNil(secureStore.readOpenAIKey())
    }

    func testKeySaveAndConnectionFailureUseSafePresentation() async throws {
        let secureStore = InMemorySecureStore()
        let model = try makeModel(
            secureStore: secureStore,
            testConnection: { throw NSError(domain: "sk-test-private-settings-key", code: 1) }
        )
        model.apiKeyInput = " sk-test-private-settings-key "

        try model.saveAPIKey()
        await model.testAPIConnection()

        XCTAssertEqual(secureStore.readOpenAIKey(), "sk-test-private-settings-key")
        XCTAssertEqual(model.apiKeyInput, "")
        XCTAssertEqual(model.apiKeyState, .failed)
        XCTAssertFalse(model.apiKeyStatusLabel.contains("sk-test-private-settings-key"))
    }

    func testDeviceSoundAndLaunchChangesReachTheirServices() throws {
        let defaults = try makeDefaults()
        let settingsStore = AppSettingsStore(defaults: defaults)
        let launchBackend = SettingsLaunchBackend(status: .notRegistered)
        let model = try makeModel(
            settingsStore: settingsStore,
            launchService: LaunchAtLoginService(backend: launchBackend),
            microphones: [
                MicrophoneDevice(id: "built-in", name: "MacBook Microphone"),
                MicrophoneDevice(id: "usb-mic", name: "USB Microphone")
            ]
        )

        model.selectMicrophone("usb-mic")
        model.setSoundEffects(false)
        model.setLaunchAtLogin(true)

        XCTAssertEqual(settingsStore.selectedMicrophoneID, "usb-mic")
        XCTAssertFalse(settingsStore.soundEffects)
        XCTAssertEqual(launchBackend.registerCallCount, 1)
        XCTAssertEqual(model.launchAtLoginState, .enabled)
    }

    func testShortcutCaptureRejectsConflictAndPersistsValidReplacement() throws {
        let settingsStore = AppSettingsStore(defaults: try makeDefaults())
        var started: [ShortcutAction] = []
        var updates: [[ShortcutAction: Shortcut]] = []
        let model = try makeModel(
            settingsStore: settingsStore,
            beginShortcutCapture: { started.append($0) },
            shortcutsChanged: { updates.append($0) }
        )

        model.beginShortcutCapture(.changeMode)
        model.acceptCapturedShortcut(
            CapturedShortcut(
                action: .changeMode,
                shortcut: AppSettings.defaults.shortcuts[.recordMeeting]!
            )
        )

        XCTAssertEqual(started, [.changeMode])
        XCTAssertEqual(model.shortcutError, "That shortcut is already used by Record Meeting.")
        XCTAssertTrue(updates.isEmpty)

        let replacement = Shortcut(key: .k, modifiers: [.control, .command])
        model.beginShortcutCapture(.changeMode)
        model.acceptCapturedShortcut(CapturedShortcut(action: .changeMode, shortcut: replacement))

        XCTAssertEqual(model.shortcuts[.changeMode], replacement)
        XCTAssertEqual(settingsStore.shortcuts[.changeMode], replacement)
        XCTAssertEqual(updates.last?[.changeMode], replacement)
    }

    func testPermissionRefreshAndRepairUseExactKind() throws {
        let permissionClient = SettingsPermissionClient()
        permissionClient.states[.microphone] = .granted
        let model = try makeModel(permissionClient: permissionClient)

        model.refresh()
        model.openPermissionSettings(.screenRecording)

        XCTAssertEqual(model.permissions.microphone, .granted)
        XCTAssertEqual(model.permissions.screenRecording, .denied)
        XCTAssertEqual(permissionClient.opened, [.screenRecording])
    }

    func testRefreshReadsLiveAPIKeyPresence() throws {
        let secureStore = InMemorySecureStore()
        let model = try makeModel(secureStore: secureStore)
        XCTAssertEqual(model.apiKeyState, .missing)

        secureStore.saveOpenAIKey("sk-test-live-key")
        model.refresh()

        XCTAssertEqual(model.apiKeyState, .saved)

        secureStore.deleteOpenAIKey()
        model.refresh()

        XCTAssertEqual(model.apiKeyState, .missing)
    }

    func testKeychainWriteFailuresHaveSafePresentationMessages() throws {
        let secret = "sk-test-private-settings-key"
        let saveStore = SettingsFailingSecureStore(
            saveError: NSError(domain: secret, code: 1)
        )
        let saveModel = try makeModel(secureStore: saveStore)
        saveModel.apiKeyInput = secret

        saveModel.saveAPIKeyForPresentation()

        XCTAssertEqual(saveModel.errorMessage, "The API key could not be saved to Keychain.")
        XCTAssertFalse(saveModel.errorMessage?.contains(secret) == true)
        XCTAssertEqual(saveModel.apiKeyState, .missing)

        let deleteStore = SettingsFailingSecureStore(
            value: secret,
            deleteError: NSError(domain: secret, code: 2)
        )
        let deleteModel = try makeModel(secureStore: deleteStore)

        deleteModel.removeAPIKeyForPresentation()

        XCTAssertEqual(deleteModel.errorMessage, "The API key could not be removed from Keychain.")
        XCTAssertFalse(deleteModel.errorMessage?.contains(secret) == true)
        XCTAssertEqual(deleteModel.apiKeyState, .saved)
    }

    func testKeychainReadFailureIsRecoverableAndUsesSafePresentation() throws {
        let secret = "sk-test-private-settings-key"
        let secureStore = SettingsFailingSecureStore(
            readError: NSError(domain: secret, code: 3)
        )

        let model = try makeModel(secureStore: secureStore)

        XCTAssertEqual(model.apiKeyState, .missing)
        XCTAssertEqual(model.apiKeyErrorMessage, "The API key status could not be read from Keychain.")
        XCTAssertFalse(model.apiKeyErrorMessage?.contains(secret) == true)
    }

    func testRemovingKeyInvalidatesAnInFlightConnectionResult() async throws {
        let gate = SettingsConnectionGate()
        let secureStore = InMemorySecureStore()
        secureStore.saveOpenAIKey("sk-test-saved-key")
        let model = try makeModel(
            secureStore: secureStore,
            testConnection: { await gate.wait() }
        )
        let task = Task { await model.testAPIConnection() }
        while model.apiKeyState != .testing { await Task.yield() }

        try model.removeAPIKey()
        await gate.open()
        await task.value

        XCTAssertEqual(model.apiKeyState, .missing)
        XCTAssertNil(secureStore.readOpenAIKey())
    }

    func testConnectionDoesNotStartWhileReplacingTheAPIKey() async throws {
        let secureStore = InMemorySecureStore()
        secureStore.saveOpenAIKey("sk-test-saved-key")
        var connectionCalls = 0
        let model = try makeModel(
            secureStore: secureStore,
            testConnection: { connectionCalls += 1 }
        )
        model.beginAPIKeyReplacement()

        await model.testAPIConnection()

        XCTAssertEqual(connectionCalls, 0)
        XCTAssertEqual(model.apiKeyState, .saved)
    }

    private func makeModel(
        secureStore: any SecureStore = InMemorySecureStore(),
        settingsStore: AppSettingsStore? = nil,
        permissionClient: SettingsPermissionClient = SettingsPermissionClient(),
        launchService: LaunchAtLoginService? = nil,
        microphones: [MicrophoneDevice] = [MicrophoneDevice(id: "built-in", name: "MacBook Microphone")],
        testConnection: @escaping @MainActor () async throws -> Void = {},
        beginShortcutCapture: @escaping @MainActor (ShortcutAction) -> Void = { _ in },
        shortcutsChanged: @escaping @MainActor ([ShortcutAction: Shortcut]) -> Void = { _ in }
    ) throws -> SettingsModel {
        let resolvedStore = try settingsStore ?? AppSettingsStore(defaults: makeDefaults())
        return SettingsModel(
            secureStore: secureStore,
            settingsStore: resolvedStore,
            permissionService: PermissionService(client: permissionClient),
            launchAtLoginService: launchService ?? LaunchAtLoginService(backend: SettingsLaunchBackend(status: .notRegistered)),
            microphoneProvider: SettingsMicrophoneProvider(devices: microphones),
            testConnection: testConnection,
            beginShortcutCapture: beginShortcutCapture,
            shortcutsChanged: shortcutsChanged
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

@MainActor
private final class SettingsPermissionClient: PermissionSystemClient {
    var states: [PermissionKind: PermissionState] = [:]
    var opened: [PermissionKind] = []

    func state(for kind: PermissionKind) -> PermissionState { states[kind] ?? .denied }
    func request(_ kind: PermissionKind) async -> PermissionState { state(for: kind) }
    func openSettings(for kind: PermissionKind) { opened.append(kind) }
}

@MainActor
private final class SettingsLaunchBackend: LaunchAtLoginBackend {
    var status: LaunchAtLoginBackendStatus
    private(set) var registerCallCount = 0

    init(status: LaunchAtLoginBackendStatus) { self.status = status }

    func register() {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() { status = .notRegistered }
    func openLoginItemsSettings() {}
}

@MainActor
private struct SettingsMicrophoneProvider: MicrophoneDeviceProviding {
    let devices: [MicrophoneDevice]
    func availableMicrophones() -> [MicrophoneDevice] { devices }
}

private final class SettingsFailingSecureStore: SecureStore, @unchecked Sendable {
    private var value: String?
    private let readError: Error?
    private let saveError: Error?
    private let deleteError: Error?

    init(
        value: String? = nil,
        readError: Error? = nil,
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.value = value
        self.readError = readError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func readOpenAIKey() throws -> String? {
        if let readError { throw readError }
        return value
    }

    func saveOpenAIKey(_ value: String) throws {
        if let saveError { throw saveError }
        self.value = value
    }

    func deleteOpenAIKey() throws {
        if let deleteError { throw deleteError }
        value = nil
    }
}

private actor SettingsConnectionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
