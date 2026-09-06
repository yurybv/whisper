#if DEBUG
import Foundation

/// Isolated launch fixture: never creates the production runtime, opens Keychain, or calls OpenAI.
@MainActor
enum OnboardingTestEnvironment {
    static func makeModel(arguments: [String]) -> OnboardingModel {
        let defaults = UserDefaults(suiteName: "Whisper.OnboardingUITests")!
        defaults.removePersistentDomain(forName: "Whisper.OnboardingUITests")
        defaults.set(!arguments.contains("--onboarding-incomplete"), forKey: OnboardingModel.completionKey)
        let valid = arguments.firstIndex(of: "--api-key-state").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        } == "valid"
        return OnboardingModel(
            store: InMemorySecureStore(),
            permissions: PermissionService(client: TestPermissions(granted: arguments.contains("--permissions-granted"))),
            defaults: defaults,
            testConnection: { if !valid { throw URLError(.userAuthenticationRequired) } }
        )
    }

    private final class TestPermissions: PermissionSystemClient {
        var granted: Bool
        init(granted: Bool) { self.granted = granted }
        func state(for kind: PermissionKind) -> PermissionState { granted ? .granted : .denied }
        func request(_ kind: PermissionKind) async -> PermissionState { state(for: kind) }
        func openSettings(for kind: PermissionKind) {}
    }
}
#endif
