import XCTest
@testable import Whisper

final class LaunchAtLoginServiceTests: XCTestCase {
    @MainActor
    func testRegistrationFailureIsUserVisibleAndCanBeRetried() throws {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.registerError = TestFailure()
        let service = LaunchAtLoginService(backend: backend)

        XCTAssertThrowsError(try service.setEnabled(true)) { error in
            XCTAssertEqual(error as? LaunchAtLoginError, .registrationFailed)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(service.state, .disabled)

        backend.registerError = nil
        try service.setEnabled(true)

        XCTAssertEqual(service.state, .enabled)
        XCTAssertEqual(backend.registerCallCount, 2)
    }

    @MainActor
    func testRequiresApprovalExposesLoginItemsRecoveryAction() {
        let backend = FakeLaunchAtLoginBackend(status: .requiresApproval)
        let service = LaunchAtLoginService(backend: backend)

        XCTAssertEqual(service.state, .requiresApproval)
        XCTAssertThrowsError(try service.setEnabled(true)) { error in
            XCTAssertEqual(error as? LaunchAtLoginError, .requiresApproval)
        }

        service.openLoginItemsSettings()

        XCTAssertEqual(backend.openSettingsCallCount, 1)
        XCTAssertEqual(backend.registerCallCount, 0)
    }
}

private struct TestFailure: Error {}

@MainActor
private final class FakeLaunchAtLoginBackend: LaunchAtLoginBackend {
    var status: LaunchAtLoginBackendStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LaunchAtLoginBackendStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        openSettingsCallCount += 1
    }
}
