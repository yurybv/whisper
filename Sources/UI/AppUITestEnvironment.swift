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

    init(arguments: [String]) throws {
        let suiteName = "Whisper.AppUITests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(!arguments.contains("--onboarding-incomplete"), forKey: OnboardingModel.completionKey)

        let validKey = Self.argumentValue(after: "--api-key-state", in: arguments) == "valid"
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
        try modeRepository.seedDefaultMode()
        let modes = try ModesModel(repository: modeRepository)

        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Whisper-AppUITests-\(UUID().uuidString)", isDirectory: true)
        let historyRepository = HistoryRepository(
            context: persistence.container.mainContext,
            appPaths: try AppPaths(rootURL: testRoot)
        )
        let home = HomeModel(historyRepository: historyRepository)
        let settings = SettingsModel(
            secureStore: secureStore,
            settingsStore: AppSettingsStore(defaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: LaunchAtLoginService(backend: AppUITestLaunchBackend()),
            microphoneProvider: AppUITestMicrophoneProvider(),
            testConnection: {
                if !validKey { throw URLError(.userAuthenticationRequired) }
            }
        )

        let initialDestination = Self.argumentValue(after: "--ui-destination", in: arguments)
            .flatMap { value in SidebarDestination.allCases.first { $0.rawValue.lowercased() == value.lowercased() } }
            ?? .home
        let window = MainWindowController { relaunch in
            AnyView(
                AppRootView(
                    onboarding: onboarding,
                    home: home,
                    modes: modes,
                    settings: settings,
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
        self.window = window
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
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
