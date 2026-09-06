import XCTest
@testable import Whisper

@MainActor
final class OnboardingModelTests: XCTestCase {
    func testConnectionIsExplicitAndSavedKeyIsNotRevealed() async throws {
        let store = InMemorySecureStore()
        store.saveOpenAIKey("sk-test-existing")
        var requests = 0
        let model = makeModel(store: store, test: { requests += 1 })
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.keyInput, "")
        model.keyInput = " sk-test-replacement "
        await model.saveAndTest()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.readOpenAIKey(), "sk-test-replacement")
        XCTAssertEqual(model.keyInput, "")
        XCTAssertEqual(model.keyStatus, "Connection verified")
    }

    func testFailureUsesSafeMessageAndAllowsLimitedSetupCompletion() async {
        let model = makeModel(test: { throw NSError(domain: "sk-test-private", code: 1) })
        model.keyInput = "sk-test-invalid"
        await model.saveAndTest()
        XCTAssertFalse(model.keyStatus.contains("sk-test"))
        XCTAssertFalse(model.isReady)
        for _ in 0..<4 { model.advance() }
        XCTAssertEqual(model.step, .ready)
        model.finish()
        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(model.defaults.bool(forKey: OnboardingModel.completionKey))
    }

    func testRefreshReadsLivePermissionAndRepairTargetsExactPane() async {
        let client = SetupPermissionClient()
        let model = makeModel(client: client)
        XCTAssertEqual(model.permissions.microphone, .denied)
        model.openSettings(for: .screenRecording)
        XCTAssertEqual(client.opened, [.screenRecording])
        client.states[.microphone] = .granted
        model.refreshPermissions()
        XCTAssertEqual(model.permissions.microphone, .granted)
        XCTAssertEqual(model.permissions.accessibility, .denied)
        await model.request(.accessibility)
        XCTAssertEqual(client.requested, [.accessibility])
        XCTAssertEqual(model.permissions.accessibility, .granted)
    }

    func testPreviewDoesNotResetCompletionButResetDoesAndBackIsBounded() {
        let model = makeModel()
        model.finish()
        model.presentSetup(reset: false)
        XCTAssertTrue(model.defaults.bool(forKey: OnboardingModel.completionKey))
        model.back()
        XCTAssertEqual(model.step, .apiKey)
        model.advance()
        model.back()
        XCTAssertEqual(model.step, .apiKey)
        model.presentSetup(reset: true)
        XCTAssertFalse(model.defaults.bool(forKey: OnboardingModel.completionKey))
    }

    func testDictationDependsOnlyOnMicrophoneAndRecoveryOpensExactStep() {
        let client = SetupPermissionClient()
        let model = makeModel(client: client)
        XCTAssertFalse(model.canDictate)
        client.states[.microphone] = .granted
        model.refreshPermissions()
        XCTAssertTrue(model.canDictate)
        model.showPermissionRecovery(.accessibility)
        XCTAssertEqual(model.step, .accessibility)
        XCTAssertTrue(model.isPresented)
    }

    func testScreenRequestOffersRelaunchEvenAfterPermissionBecomesGranted() async {
        let model = makeModel()
        XCTAssertFalse(model.screenSettingsOpened)
        await model.request(.screenRecording)
        XCTAssertEqual(model.permissions.screenRecording, .granted)
        XCTAssertTrue(model.screenSettingsOpened)
    }

    private func makeModel(
        store: any SecureStore = InMemorySecureStore(),
        client: SetupPermissionClient = SetupPermissionClient(),
        test: @escaping @MainActor () async throws -> Void = {}
    ) -> OnboardingModel {
        let defaults = UserDefaults(suiteName: "WhisperOnboardingTests.\(UUID())")!
        return OnboardingModel(store: store, permissions: PermissionService(client: client), defaults: defaults, testConnection: test)
    }
}

@MainActor
private final class SetupPermissionClient: PermissionSystemClient {
    var states: [PermissionKind: PermissionState] = [:]
    var opened: [PermissionKind] = []
    var requested: [PermissionKind] = []
    func state(for kind: PermissionKind) -> PermissionState { states[kind] ?? .denied }
    func request(_ kind: PermissionKind) async -> PermissionState {
        requested.append(kind)
        states[kind] = .granted
        return .granted
    }
    func openSettings(for kind: PermissionKind) { opened.append(kind) }
}
