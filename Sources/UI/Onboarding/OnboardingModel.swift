import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case apiKey, microphone, screenRecording, accessibility, ready
    }

    static let completionKey = "onboardingCompleted"
    let defaults: UserDefaults
    private let store: any SecureStore
    private let permissionService: PermissionService
    private let testConnection: @MainActor () async throws -> Void
    var keyInput = ""
    private(set) var keyStatus = "Key not tested this session"
    private(set) var isTesting = false
    private(set) var keyVerified = false
    private(set) var permissions: PermissionSnapshot
    private(set) var step: Step = .apiKey
    private(set) var isPresented: Bool
    private(set) var screenSettingsOpened = false
    private(set) var inputMonitoringSettingsOpened = false
    private(set) var requestingPermission = false

    init(store: any SecureStore, permissions: PermissionService, defaults: UserDefaults,
         testConnection: @escaping @MainActor () async throws -> Void) {
        self.store = store
        permissionService = permissions
        self.defaults = defaults
        self.testConnection = testConnection
        self.permissions = permissions.snapshot()
        isPresented = !defaults.bool(forKey: Self.completionKey)
    }

    var canDictate: Bool { permissions.microphone == .granted }
    private(set) var completionGeneration = 0

    func showPermissionRecovery(_ kind: PermissionKind) {
        presentSetup(reset: false)
        switch kind {
        case .microphone: step = .microphone
        case .screenRecording: step = .screenRecording
        case .accessibility, .inputMonitoring: step = .accessibility
        }
    }

    var isReady: Bool {
        keyVerified && PermissionKind.allCases.allSatisfy { permissions[$0] == .granted }
    }

    func saveAndTest() async {
        guard !isTesting else { return }
        isTesting = true
        keyVerified = false
        keyStatus = "Testing connection…"
        defer { isTesting = false }
        do {
            let candidate = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            keyInput = ""
            if !candidate.isEmpty { try store.saveOpenAIKey(candidate) }
            try await testConnection()
            keyVerified = true
            keyStatus = "Connection verified"
        } catch {
            keyStatus = "Connection could not be verified. Check your key and network, then try again."
        }
    }

    func refreshPermissions() { permissions = permissionService.snapshot() }

    func request(_ kind: PermissionKind) async {
        guard !requestingPermission else { return }
        if kind == .screenRecording { screenSettingsOpened = true }
        if kind == .inputMonitoring { inputMonitoringSettingsOpened = true }
        requestingPermission = true
        defer { requestingPermission = false }
        _ = await permissionService.request(kind)
        refreshPermissions()
    }

    func openSettings(for kind: PermissionKind) {
        if kind == .screenRecording { screenSettingsOpened = true }
        if kind == .inputMonitoring { inputMonitoringSettingsOpened = true }
        permissionService.openSettings(for: kind)
    }

    func advance() {
        guard !isTesting, !requestingPermission else { return }
        refreshPermissions()
        step = Step(rawValue: min(step.rawValue + 1, Step.ready.rawValue)) ?? .ready
    }

    func back() {
        guard !isTesting, !requestingPermission else { return }
        step = Step(rawValue: max(0, step.rawValue - 1)) ?? .apiKey
    }

    func finish() {
        completionGeneration += 1
        defaults.set(true, forKey: Self.completionKey)
        close()
    }

    func close() {
        keyInput = ""
        isPresented = false
    }

    func presentSetup(reset: Bool) {
        if reset { defaults.set(false, forKey: Self.completionKey) }
        keyInput = ""
        step = .apiKey
        refreshPermissions()
        isPresented = true
    }
}
