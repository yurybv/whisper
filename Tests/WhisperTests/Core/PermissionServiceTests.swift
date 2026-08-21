import XCTest
@testable import Whisper

final class PermissionServiceTests: XCTestCase {
    @MainActor
    func testSnapshotQueriesStatusesWithoutRequestingPermissions() {
        let client = FakePermissionSystemClient(
            states: [
                .microphone: .notDetermined,
                .screenRecording: .denied,
                .accessibility: .granted
            ]
        )
        let service = PermissionService(client: client)

        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.microphone, .notDetermined)
        XCTAssertEqual(snapshot.screenRecording, .denied)
        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertEqual(Set(client.queriedKinds), Set(PermissionKind.allCases))
        XCTAssertTrue(client.requestedKinds.isEmpty)
    }

    @MainActor
    func testRequestTargetsOnlyTheSelectedPermission() async {
        let client = FakePermissionSystemClient(
            states: [.microphone: .granted]
        )
        let service = PermissionService(client: client)

        let state = await service.request(.microphone)

        XCTAssertEqual(state, .granted)
        XCTAssertEqual(client.requestedKinds, [.microphone])
        XCTAssertTrue(client.openedSettingsKinds.isEmpty)
    }

    @MainActor
    func testOpenSettingsTargetsOnlyTheSelectedPermission() {
        let client = FakePermissionSystemClient()
        let service = PermissionService(client: client)

        service.openSettings(for: .screenRecording)

        XCTAssertEqual(client.openedSettingsKinds, [.screenRecording])
        XCTAssertTrue(client.requestedKinds.isEmpty)
    }
}

@MainActor
private final class FakePermissionSystemClient: PermissionSystemClient {
    private let states: [PermissionKind: PermissionState]
    private(set) var queriedKinds: [PermissionKind] = []
    private(set) var requestedKinds: [PermissionKind] = []
    private(set) var openedSettingsKinds: [PermissionKind] = []

    init(states: [PermissionKind: PermissionState] = [:]) {
        self.states = states
    }

    func state(for kind: PermissionKind) -> PermissionState {
        queriedKinds.append(kind)
        return states[kind] ?? .denied
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        requestedKinds.append(kind)
        return states[kind] ?? .denied
    }

    func openSettings(for kind: PermissionKind) {
        openedSettingsKinds.append(kind)
    }
}
