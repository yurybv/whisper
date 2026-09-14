@preconcurrency import CoreMedia
import Foundation

struct MeetingCaptureConfiguration: Sendable, Equatable {
    let meetingID: UUID
    let microphoneDeviceID: String?
    let maximumDuration: TimeInterval

    init(
        meetingID: UUID,
        microphoneDeviceID: String? = nil,
        maximumDuration: TimeInterval = 10_800
    ) {
        self.meetingID = meetingID
        self.microphoneDeviceID = microphoneDeviceID
        self.maximumDuration = maximumDuration
    }
}

enum MeetingAudioSource: String, Sendable, Equatable, Hashable {
    case microphone
    case systemAudio
}

struct MeetingAudioLevels: Sendable, Equatable {
    let microphone: Float
    let systemAudio: Float
    let elapsedTime: TimeInterval
}

struct CapturedMeeting: Sendable, Equatable {
    let microphoneURL: URL
    let systemAudioURL: URL
    let microphoneStartOffset: TimeInterval
    let systemAudioStartOffset: TimeInterval
    let startedAt: Date
    let endedAt: Date
}

enum MeetingCaptureInterruptionReason: Sendable, Equatable {
    case microphone
    case systemAudio
    case bothSources
}

struct MeetingCaptureFailure: Error, Sendable, Equatable {
    let unavailableSource: MeetingCaptureInterruptionReason
    let microphoneURL: URL?
    let systemAudioURL: URL?
    let microphoneStartOffset: TimeInterval
    let systemAudioStartOffset: TimeInterval
    let startedAt: Date
    let endedAt: Date
}

enum MeetingCaptureCompletion: Sendable, Equatable {
    case completed(CapturedMeeting)
    case failed(MeetingCaptureFailure)
}

extension MeetingCaptureFailure: LocalizedError {
    var errorDescription: String? {
        switch unavailableSource {
        case .microphone:
            "The microphone became unavailable. Available audio was preserved."
        case .systemAudio:
            "System audio capture stopped. Available audio was preserved."
        case .bothSources:
            "Both audio sources stopped. Available audio was preserved."
        }
    }
}

enum MeetingRecorderError: Error, Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case invalidMaximumDuration
    case insufficientDiskSpace(availableBytes: Int64)
    case cannotCreateRecordingDirectory
    case recordingAlreadyExists
    case captureUnavailable
}

extension MeetingRecorderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A meeting recording is already active."
        case .notRecording:
            "No meeting recording is active."
        case .invalidMaximumDuration:
            "The meeting duration must be greater than zero."
        case .insufficientDiskSpace:
            "At least 2 GB of free space is required to record a meeting."
        case .cannotCreateRecordingDirectory:
            "Whisper could not create the meeting recording directory."
        case .recordingAlreadyExists:
            "A recording already exists for this meeting."
        case .captureUnavailable:
            "Whisper could not start system audio capture."
        }
    }
}

protocol MeetingRecorder: Sendable {
    func start(configuration: MeetingCaptureConfiguration) async throws
    func levels() async -> AsyncStream<MeetingAudioLevels>
    func completions() async -> AsyncStream<MeetingCaptureCompletion>
    func stop() async throws -> CapturedMeeting
    func interrupt(reason: MeetingCaptureInterruptionReason) async
    func cancel() async
}

protocol MeetingTrackWriter: Sendable {
    func append(_ sampleBuffer: CMSampleBuffer) throws
    func finish() async throws -> URL
    func cancel()
}

protocol MeetingCaptureBackend: Sendable {
    func start(
        microphoneDeviceID: String?,
        sampleHandler: @escaping @Sendable (MeetingAudioSource, CMSampleBuffer) -> Void,
        interruptionHandler: @escaping @Sendable (MeetingAudioSource) -> Void
    ) async throws
    func stop() async
}

protocol MeetingDeadline: Sendable {
    func cancel()
}

protocol MeetingDeadlineScheduling: Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> any MeetingDeadline
}
