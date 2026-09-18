#if DEBUG
import Foundation
import SwiftUI

/// Isolated launch fixture: it never opens production storage, Keychain, permissions, or the network.
@MainActor
final class AppUITestEnvironment {
    let window: MainWindowController

    private let persistence: PersistenceController
    private let onboarding: OnboardingModel
    private let home: HomeModel
    private let modes: ModesModel
    private let settings: SettingsModel
    private let recordings: RecordingsModel
    private let history: HistorySearchModel

    init(arguments: [String]) throws {
        let suiteName = "Whisper.AppUITests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(!arguments.contains("--onboarding-incomplete"), forKey: OnboardingModel.completionKey)

        let validKey = Self.argumentValue(after: "--api-key-state", in: arguments) == "valid"
        let connectionResult = Self.argumentValue(after: "--connection-result", in: arguments)
        let secureStore = InMemorySecureStore()
        if validKey {
            secureStore.saveOpenAIKey("ui-test-key")
        }
        let permissionService = PermissionService(
            client: AppUITestPermissions(granted: arguments.contains("--permissions-granted"))
        )
        let onboarding = OnboardingModel(
            store: secureStore,
            permissions: permissionService,
            defaults: defaults,
            testConnection: {
                if !validKey { throw URLError(.userAuthenticationRequired) }
            }
        )

        let persistence = try PersistenceController(inMemory: true)
        let modeRepository = ModeRepository(
            context: persistence.container.mainContext,
            userDefaults: defaults
        )
        try modeRepository.seedBuiltInModes()
        if arguments.contains("--long-content") {
            _ = try modeRepository.create(
                ModeDraft(
                    name: "Long mode 12345 67890 12345 67890 12345 67890",
                    instructions: "12345 67890 12345 67890 12345 67890 12345 67890",
                    languageHint: nil,
                    isEnabled: false,
                    sortIndex: 1
                )
            )
        }
        let modes = try ModesModel(repository: modeRepository)

        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Whisper-AppUITests-\(UUID().uuidString)", isDirectory: true)
        let appPaths = try AppPaths(rootURL: testRoot)
        let historyRepository = HistoryRepository(
            context: persistence.container.mainContext,
            appPaths: appPaths
        )
        let home = HomeModel(historyRepository: historyRepository)
        let history = HistorySearchModel(repository: historyRepository)
        let appSettingsStore = AppSettingsStore(defaults: defaults)
        let settings = SettingsModel(
            secureStore: secureStore,
            settingsStore: appSettingsStore,
            permissionService: permissionService,
            launchAtLoginService: LaunchAtLoginService(backend: AppUITestLaunchBackend()),
            microphoneProvider: AppUITestMicrophoneProvider(),
            testConnection: {
                if connectionResult == "testing" {
                    try await Task.sleep(for: .seconds(600))
                }
                if connectionResult == "failed" {
                    try await Task.sleep(for: .milliseconds(200))
                }
                if !validKey || connectionResult == "failed" {
                    throw URLError(.userAuthenticationRequired)
                }
            }
        )
        if arguments.contains("--shortcut-conflict") {
            settings.beginShortcutCapture(.changeMode)
            settings.acceptCapturedShortcut(
                CapturedShortcut(
                    action: .changeMode,
                    shortcut: AppSettings.defaults.shortcuts[.recordMeeting]!
                )
            )
        }
        if connectionResult != nil {
            Task { await settings.testAPIConnection() }
        }
        let recordingDiskState: DiskSpaceMonitor.State = arguments.contains("--recording-low-disk")
            ? .blocked(availableBytes: 1_500_000_000)
            : .ready(availableBytes: 10_000_000_000)
        let recordingDriver = AppUITestRecordingDriver()
        let recordings = RecordingsModel(
            settingsStore: appSettingsStore,
            settings: settings,
            diskState: { recordingDiskState },
            start: { [recordingDriver] _, _, _, _ in recordingDriver.start() },
            stop: { [recordingDriver] in recordingDriver.stop() },
            cancel: { true },
            retry: { _ in },
            now: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )
        recordingDriver.model = recordings
        if arguments.contains("--recording-active") {
            recordings.consume(.recording(meetingID: UUID()))
            recordings.consume(
                MeetingAudioLevels(
                    microphone: 0.7,
                    systemAudio: 0.45,
                    elapsedTime: 2_238
                )
            )
        } else if arguments.contains("--recording-finalizing") {
            recordings.consume(.finalizing(meetingID: UUID()))
        }

        let initialDestination = Self.argumentValue(after: "--ui-destination", in: arguments)
            .flatMap { value in SidebarDestination.allCases.first { $0.rawValue.lowercased() == value.lowercased() } }
            ?? .home
        let window = MainWindowController(preferredScreen: Self.builtInScreen) { relaunch in
            AnyView(
                AppRootView(
                    onboarding: onboarding,
                    home: home,
                    modes: modes,
                    settings: settings,
                    recordings: recordings,
                    history: history,
                    initialDestination: initialDestination,
                    relaunch: relaunch,
                    startDictation: {},
                    changeMode: {},
                    recordMeeting: {}
                )
            )
        }

        self.persistence = persistence
        self.onboarding = onboarding
        self.home = home
        self.modes = modes
        self.settings = settings
        self.recordings = recordings
        self.history = history
        self.window = window
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        }
    }
}

@MainActor
private final class AppUITestRecordingDriver {
    weak var model: RecordingsModel?
    private let meetingID = UUID()

    func start() -> UUID {
        Task { [weak model] in
            try? await Task.sleep(for: .milliseconds(150))
            model?.consume(
                MeetingAudioLevels(
                    microphone: 0.7,
                    systemAudio: 0.45,
                    elapsedTime: 2_238
                )
            )
        }
        return meetingID
    }

    func stop() {
        Task { [weak model, meetingID] in
            try? await Task.sleep(for: .seconds(2))
            model?.consume(.transcribing(meetingID: meetingID, completed: 1, total: 2))
            try? await Task.sleep(for: .seconds(2))
            model?.consume(.ready(meetingID: meetingID))
        }
    }
}

@MainActor
private final class AppUITestPermissions: PermissionSystemClient {
    private let granted: Bool

    init(granted: Bool) {
        self.granted = granted
    }

    func state(for kind: PermissionKind) -> PermissionState { granted ? .granted : .denied }
    func request(_ kind: PermissionKind) async -> PermissionState { state(for: kind) }
    func openSettings(for kind: PermissionKind) {}
}

@MainActor
private final class AppUITestLaunchBackend: LaunchAtLoginBackend {
    var status: LaunchAtLoginBackendStatus = .notRegistered

    func register() { status = .enabled }
    func unregister() { status = .notRegistered }
    func openLoginItemsSettings() {}
}

@MainActor
private struct AppUITestMicrophoneProvider: MicrophoneDeviceProviding {
    func availableMicrophones() -> [MicrophoneDevice] {
        [MicrophoneDevice(id: "built-in", name: "MacBook Microphone")]
    }
}
#endif
