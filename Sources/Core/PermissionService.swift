import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum PermissionKind: String, CaseIterable, Sendable, Codable, Hashable {
    case microphone
    case screenRecording
    case accessibility
}

enum PermissionState: String, Sendable, Codable, Equatable {
    case granted
    case denied
    case notDetermined
}

struct PermissionSnapshot: Sendable, Equatable {
    let microphone: PermissionState
    let screenRecording: PermissionState
    let accessibility: PermissionState

    subscript(kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            microphone
        case .screenRecording:
            screenRecording
        case .accessibility:
            accessibility
        }
    }
}

@MainActor
protocol PermissionSystemClient {
    func state(for kind: PermissionKind) -> PermissionState
    func request(_ kind: PermissionKind) async -> PermissionState
    func openSettings(for kind: PermissionKind)
}

@MainActor
final class PermissionService {
    private let client: any PermissionSystemClient

    init(client: any PermissionSystemClient = MacPermissionSystemClient()) {
        self.client = client
    }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: client.state(for: .microphone),
            screenRecording: client.state(for: .screenRecording),
            accessibility: client.state(for: .accessibility)
        )
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        await client.request(kind)
    }

    func openSettings(for kind: PermissionKind) {
        client.openSettings(for: kind)
    }
}

@MainActor
final class MacPermissionSystemClient: PermissionSystemClient {
    func state(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone:
            microphoneState
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .microphone:
            return await withCheckedContinuation { (continuation: CheckedContinuation<PermissionState, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            let options = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
        }
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = URL(string: settingsURLString(for: kind)) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var microphoneState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private func settingsURLString(for kind: PermissionKind) -> String {
        let anchor = switch kind {
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }
}
