import Foundation
import ServiceManagement

enum LaunchAtLoginBackendStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum LaunchAtLoginState: Sendable, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LaunchAtLoginError: LocalizedError, Sendable, Equatable {
    case registrationFailed
    case unregistrationFailed
    case requiresApproval

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "Whisper could not be added to Login Items. Try again or enable it in System Settings."
        case .unregistrationFailed:
            "Whisper could not be removed from Login Items. Try again or disable it in System Settings."
        case .requiresApproval:
            "Whisper needs approval in System Settings before it can open at login."
        }
    }
}

@MainActor
protocol LaunchAtLoginBackend {
    var status: LaunchAtLoginBackendStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
final class LaunchAtLoginService {
    private let backend: any LaunchAtLoginBackend

    init(backend: any LaunchAtLoginBackend = ServiceManagementLaunchAtLoginBackend()) {
        self.backend = backend
    }

    var state: LaunchAtLoginState {
        switch backend.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch backend.status {
            case .enabled:
                return
            case .requiresApproval:
                throw LaunchAtLoginError.requiresApproval
            case .notRegistered, .notFound:
                do {
                    try backend.register()
                } catch {
                    throw LaunchAtLoginError.registrationFailed
                }
            }
        } else {
            switch backend.status {
            case .notRegistered, .notFound:
                return
            case .enabled, .requiresApproval:
                do {
                    try backend.unregister()
                } catch {
                    throw LaunchAtLoginError.unregistrationFailed
                }
            }
        }
    }

    func openLoginItemsSettings() {
        backend.openLoginItemsSettings()
    }
}

@MainActor
final class ServiceManagementLaunchAtLoginBackend: LaunchAtLoginBackend {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var status: LaunchAtLoginBackendStatus {
        switch appService.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try appService.register()
    }

    func unregister() throws {
        try appService.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
