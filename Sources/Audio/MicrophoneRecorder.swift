import Foundation

struct CapturedAudio: Sendable, Equatable {
    let fileURL: URL
    let duration: TimeInterval
    let peakLevel: Float
    let containsSpeech: Bool
}

protocol MicrophoneRecorder: Sendable {
    func start(deviceID: String?) async throws
    func levels() async -> AsyncStream<Float>
    func stop() async throws -> CapturedAudio
    func cancel() async
}

protocol AudioCaptureBackend: Sendable {
    func start(
        deviceID: String?,
        samplesHandler: @escaping @Sendable ([Float]) -> Void,
        deviceLossHandler: @escaping @Sendable () -> Void
    ) throws
    func stop()
}

enum MicrophoneRecorderError: Error, Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case deviceUnavailable
    case cannotCreateAudioFile
    case cannotWriteAudioFile
}

extension MicrophoneRecorderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A microphone recording is already active."
        case .notRecording:
            "No microphone recording is active."
        case .deviceUnavailable:
            "The selected microphone is unavailable."
        case .cannotCreateAudioFile:
            "Whisper could not create a temporary audio file."
        case .cannotWriteAudioFile:
            "Whisper could not write the microphone recording."
        }
    }
}
