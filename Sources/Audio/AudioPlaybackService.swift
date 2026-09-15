import AVFoundation
import Foundation

enum MeetingPlaybackSource: String, CaseIterable, Identifiable, Sendable {
    case mix = "Mix"
    case microphone = "You"
    case systemAudio = "Others"

    var id: String { rawValue }
}

struct AudioPlaybackTrack: Equatable, Sendable {
    let url: URL
    let offset: TimeInterval
}

struct AudioPlaybackPlan: Equatable, Sendable {
    let source: MeetingPlaybackSource
    let tracks: [AudioPlaybackTrack]
}

enum AudioPlaybackError: LocalizedError, Equatable {
    case sourceUnavailable
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "The selected recording source is unavailable."
        case .invalidAudio: "The selected recording could not be prepared for playback."
        }
    }
}

@MainActor
protocol AudioPlaybackTransport: AnyObject {
    func play(_ plan: AudioPlaybackPlan) async throws
    func stop()
}

@MainActor
final class AVPlayerPlaybackTransport: AudioPlaybackTransport {
    private var player: AVPlayer?
    private var generation = 0

    func play(_ plan: AudioPlaybackPlan) async throws {
        generation += 1
        let requestGeneration = generation
        player?.pause()
        player = nil
        let item: AVPlayerItem
        if plan.tracks.count == 1, let track = plan.tracks.first, track.offset == 0 {
            item = AVPlayerItem(url: track.url)
        } else {
            let composition = AVMutableComposition()
            for plannedTrack in plan.tracks {
                let asset = AVURLAsset(url: plannedTrack.url)
                let duration = try await asset.load(.duration)
                guard generation == requestGeneration else { throw CancellationError() }
                guard
                    duration.isNumeric,
                    duration.seconds > 0,
                    let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
                    let destinationTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                else {
                    throw AudioPlaybackError.invalidAudio
                }
                try destinationTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: CMTime(seconds: max(0, plannedTrack.offset), preferredTimescale: 600)
                )
            }
            item = AVPlayerItem(asset: composition)
        }
        guard generation == requestGeneration else { throw CancellationError() }
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
    }

    func stop() {
        generation += 1
        player?.pause()
        player = nil
    }
}

@MainActor
final class AudioPlaybackService {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let transport: any AudioPlaybackTransport

    init(
        paths: AppPaths,
        fileManager: FileManager = .default,
        transport: (any AudioPlaybackTransport)? = nil
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.transport = transport ?? AVPlayerPlaybackTransport()
    }

    func availableSources(for meeting: MeetingSnapshot) -> [MeetingPlaybackSource] {
        let microphone = track(
            relativePath: meeting.microphoneRelativePath,
            meetingID: meeting.id,
            offset: meeting.microphoneStartOffset
        )
        let systemAudio = track(
            relativePath: meeting.systemAudioRelativePath,
            meetingID: meeting.id,
            offset: meeting.systemAudioStartOffset
        )
        var sources: [MeetingPlaybackSource] = []
        if microphone != nil, systemAudio != nil { sources.append(.mix) }
        if microphone != nil { sources.append(.microphone) }
        if systemAudio != nil { sources.append(.systemAudio) }
        return sources
    }

    func play(meeting: MeetingSnapshot, source: MeetingPlaybackSource) async throws {
        let microphone = track(
            relativePath: meeting.microphoneRelativePath,
            meetingID: meeting.id,
            offset: meeting.microphoneStartOffset
        )
        let systemAudio = track(
            relativePath: meeting.systemAudioRelativePath,
            meetingID: meeting.id,
            offset: meeting.systemAudioStartOffset
        )
        let tracks: [AudioPlaybackTrack]
        switch source {
        case .mix:
            guard let microphone, let systemAudio else { throw AudioPlaybackError.sourceUnavailable }
            tracks = [microphone, systemAudio]
        case .microphone:
            guard let microphone else { throw AudioPlaybackError.sourceUnavailable }
            tracks = [microphone]
        case .systemAudio:
            guard let systemAudio else { throw AudioPlaybackError.sourceUnavailable }
            tracks = [systemAudio]
        }
        try await transport.play(AudioPlaybackPlan(source: source, tracks: tracks))
    }

    func stop() {
        transport.stop()
    }

    private func track(
        relativePath: String,
        meetingID: UUID,
        offset: TimeInterval
    ) -> AudioPlaybackTrack? {
        guard !relativePath.isEmpty,
              let url = try? paths.recordingFileURL(relativePath: relativePath, meetingID: meetingID),
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return AudioPlaybackTrack(url: url, offset: max(0, offset))
    }
}
