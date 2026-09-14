import Foundation
import Observation

enum RecordingResultLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case english
    case russian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .english: "English"
        case .russian: "Russian"
        }
    }

    var storedValue: String? {
        switch self {
        case .automatic: nil
        case .english: "English"
        case .russian: "Russian"
        }
    }

    init(storedValue: String?) {
        switch storedValue {
        case "English": self = .english
        case "Russian": self = .russian
        default: self = .automatic
        }
    }
}

@MainActor
@Observable
final class RecordingsModel {
    typealias DiskState = @MainActor () throws -> DiskSpaceMonitor.State
    typealias Start = @MainActor (
        _ title: String,
        _ instructions: String,
        _ resultLanguage: String?,
        _ microphoneID: String?
    ) async throws -> UUID
    typealias Stop = @MainActor () async throws -> Void
    typealias Cancel = @MainActor () async -> Bool
    typealias Now = @MainActor () -> Date

    private let settingsStore: AppSettingsStore
    private let settings: any RecordingSettingsProviding
    private let diskStateProvider: DiskState
    private let start: Start
    private let stop: Stop
    private let cancel: Cancel
    private let now: Now

    var instructions: String {
        didSet { settingsStore.recordingInstructions = instructions }
    }
    var resultLanguage: RecordingResultLanguage {
        didSet { settingsStore.recordingResultLanguage = resultLanguage.storedValue }
    }
    private(set) var state: MeetingRuntimeState = .idle
    private(set) var microphoneLevel: Float = 0
    private(set) var systemAudioLevel: Float = 0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var storageState: DiskSpaceMonitor.State?
    private(set) var localErrorMessage: String?
    private(set) var isActionPending = false

    init(
        settingsStore: AppSettingsStore,
        settings: any RecordingSettingsProviding,
        diskState: @escaping DiskState,
        start: @escaping Start,
        stop: @escaping Stop,
        cancel: @escaping Cancel,
        now: @escaping Now = Date.init
    ) {
        self.settingsStore = settingsStore
        self.settings = settings
        diskStateProvider = diskState
        self.start = start
        self.stop = stop
        self.cancel = cancel
        self.now = now
        instructions = settingsStore.recordingInstructions
        resultLanguage = RecordingResultLanguage(
            storedValue: settingsStore.recordingResultLanguage
        )
        refresh()
    }

    var microphones: [MicrophoneDevice] { settings.microphones }
    var selectedMicrophoneID: String? { settings.selectedMicrophoneID }
    var selectedMicrophoneName: String { settings.selectedMicrophoneName }
    var recordingShortcut: String {
        settings.shortcuts[.recordMeeting]?.displayName ?? "Not set"
    }
    var microphonePermission: PermissionState { settings.permissions.microphone }
    var screenRecordingPermission: PermissionState { settings.permissions.screenRecording }

    var elapsedLabel: String {
        let seconds = max(0, min(10_800, Int(elapsedTime.rounded(.down))))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds / 60) % 60,
            seconds % 60
        )
    }

    var statusTitle: String {
        switch state {
        case .idle: "Ready to record"
        case .recording: "Recording"
        case .finalizing: "Finalizing"
        case .captured: "Captured"
        case .transcribing: "Transcribing"
        case .processing: "Processing"
        case .ready: "Ready"
        case .failed: "Recording needs attention"
        }
    }

    var statusMessage: String {
        if let localErrorMessage { return localErrorMessage }
        if case let .blocked(availableBytes) = storageState {
            return "At least 2 GB of free disk space is required. \(Self.capacity(availableBytes)) is available."
        }
        if case let .warning(availableBytes) = storageState, state == .idle {
            return "Disk space is running low (\(Self.capacity(availableBytes)) available). Source audio will still be saved locally."
        }
        return switch state {
        case .idle:
            "Microphone and Mac system audio will be captured as separate local tracks."
        case .recording:
            "Microphone and system audio are being written continuously to this Mac."
        case .finalizing:
            "Finishing both local audio tracks before transcription begins."
        case .captured:
            "Audio is safely stored locally and is waiting for transcription."
        case let .transcribing(_, completed, total):
            total > 0 ? "Transcribing \(completed) of \(total) chunks." : "Preparing audio chunks for transcription."
        case .processing:
            "Applying the saved processing instructions."
        case .ready:
            "The recording transcript and processed result are ready in local history."
        case let .failed(_, message):
            message
        }
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording: "Stop Recording"
        case .finalizing: "Finalizing…"
        case .captured, .transcribing, .processing: "Processing…"
        default: "Start Recording"
        }
    }

    var canEditConfiguration: Bool {
        switch state {
        case .recording, .finalizing: false
        default: !isActionPending
        }
    }

    var canToggleRecording: Bool {
        guard !isActionPending else { return false }
        switch state {
        case .recording: return true
        case .finalizing, .captured, .transcribing, .processing: return false
        default:
            guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  microphonePermission == .granted,
                  screenRecordingPermission == .granted else { return false }
            if case .blocked = storageState { return false }
            return storageState != nil
        }
    }

    var hasActionError: Bool { localErrorMessage != nil }

    func refresh() {
        settings.refresh()
        do {
            storageState = try diskStateProvider()
        } catch {
            storageState = nil
            localErrorMessage = "Whisper could not check available disk space."
        }
    }

    func selectMicrophone(_ id: String?) {
        settings.selectMicrophone(id)
    }

    func openPermissionSettings(_ kind: PermissionKind) {
        settings.openPermissionSettings(kind)
    }

    func toggleRecording() async {
        guard !isActionPending else { return }
        localErrorMessage = nil
        switch state {
        case let .recording(meetingID):
            isActionPending = true
            state = .finalizing(meetingID: meetingID)
            defer { isActionPending = false }
            do {
                try await stop()
            } catch {
                if state == .finalizing(meetingID: meetingID) {
                    state = .recording(meetingID: meetingID)
                }
                localErrorMessage = Self.message(for: error)
            }
        case .finalizing:
            return
        case .captured, .transcribing, .processing:
            return
        default:
            refresh()
            guard validateStart() else { return }
            isActionPending = true
            defer { isActionPending = false }
            do {
                let meetingID = try await start(
                    "Meeting · \(now().formatted(date: .abbreviated, time: .shortened))",
                    instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                    resultLanguage.storedValue,
                    settings.selectedMicrophoneID
                )
                state = .recording(meetingID: meetingID)
                elapsedTime = 0
                microphoneLevel = 0
                systemAudioLevel = 0
            } catch {
                localErrorMessage = Self.message(for: error)
            }
        }
    }

    @discardableResult
    func cancelRecording() async -> Bool {
        guard case .recording = state else { return false }
        guard await cancel() else { return false }
        state = .idle
        elapsedTime = 0
        microphoneLevel = 0
        systemAudioLevel = 0
        localErrorMessage = nil
        refresh()
        return true
    }

    func consume(_ newState: MeetingRuntimeState) {
        if let activeMeetingID = state.activeCaptureMeetingID,
           let incomingMeetingID = newState.meetingID,
           incomingMeetingID != activeMeetingID {
            return
        }
        apply(newState)
    }

    func consumeAuthoritative(_ newState: MeetingRuntimeState) {
        apply(newState)
    }

    private func apply(_ newState: MeetingRuntimeState) {
        state = newState
        if case .recording = newState {
            localErrorMessage = nil
        }
        if newState == .idle {
            elapsedTime = 0
            microphoneLevel = 0
            systemAudioLevel = 0
        }
    }

    func consume(_ levels: MeetingAudioLevels) {
        guard case .recording = state else { return }
        microphoneLevel = min(max(levels.microphone, 0), 1)
        systemAudioLevel = min(max(levels.systemAudio, 0), 1)
        elapsedTime = min(max(levels.elapsedTime, 0), 10_800)
    }

    private func validateStart() -> Bool {
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            localErrorMessage = "Enter processing instructions before recording."
            return false
        }
        guard microphonePermission == .granted else {
            localErrorMessage = "Microphone access is required. Open System Settings → Privacy & Security → Microphone."
            return false
        }
        guard screenRecordingPermission == .granted else {
            localErrorMessage = "Screen Recording access is required to capture Mac system audio."
            return false
        }
        if case let .blocked(availableBytes) = storageState {
            localErrorMessage = "At least 2 GB of free disk space is required. \(Self.capacity(availableBytes)) is available."
            return false
        }
        guard storageState != nil else {
            localErrorMessage = "Whisper could not verify available disk space."
            return false
        }
        return true
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return "Whisper could not change the recording state."
    }

    private static func capacity(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

extension MeetingRuntimeState {
    var meetingID: UUID? {
        switch self {
        case .idle: nil
        case let .recording(meetingID),
             let .finalizing(meetingID),
             let .captured(meetingID),
             let .processing(meetingID),
             let .ready(meetingID): meetingID
        case let .transcribing(meetingID, _, _),
             let .failed(meetingID, _): meetingID
        }
    }

    var activeCaptureMeetingID: UUID? {
        switch self {
        case let .recording(meetingID), let .finalizing(meetingID): meetingID
        default: nil
        }
    }
}
