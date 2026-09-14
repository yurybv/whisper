@preconcurrency import AVFoundation
import AudioToolbox
@preconcurrency import CoreMedia
import Foundation

enum SampleBufferAudioWriterError: Error, Sendable, Equatable {
    case noSamples
    case invalidSampleBuffer
    case cannotCreateWriter
    case cannotAddInput
    case cannotStartWriting
    case inputNotReady
    case cannotRetimestamp
    case cannotAppend
    case cannotFinish
    case outputMissing
    case alreadyFinished
}

extension SampleBufferAudioWriterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noSamples:
            "No audio samples were captured."
        case .invalidSampleBuffer:
            "The captured audio sample is invalid."
        case .cannotCreateWriter:
            "Whisper could not create the audio track writer."
        case .cannotAddInput:
            "Whisper could not configure the audio track writer."
        case .cannotStartWriting:
            "Whisper could not start writing the audio track."
        case .inputNotReady:
            "The audio track writer could not keep up with capture."
        case .cannotRetimestamp:
            "Whisper could not align the captured audio timestamps."
        case .cannotAppend:
            "Whisper could not append captured audio."
        case .cannotFinish:
            "Whisper could not finalize the audio track."
        case .outputMissing:
            "The finalized audio track is missing."
        case .alreadyFinished:
            "The audio track was already finalized."
        }
    }
}

final class SampleBufferAudioWriter: MeetingTrackWriter, @unchecked Sendable {
    private let outputURL: URL
    private let queue: DispatchQueue
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var hasSamples = false
    private var isFinishing = false

    init(outputURL: URL) {
        self.outputURL = outputURL
        queue = DispatchQueue(label: "dev.yury.whisper.audio-writer.\(UUID().uuidString)")
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        try queue.sync {
            guard !isFinishing else {
                throw SampleBufferAudioWriterError.alreadyFinished
            }
            guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else {
                throw SampleBufferAudioWriterError.invalidSampleBuffer
            }
            if writer == nil {
                try prepareWriter(for: sampleBuffer)
            }
            guard let writer, let input, let firstPresentationTime else {
                throw SampleBufferAudioWriterError.cannotCreateWriter
            }
            guard writer.status == .writing else {
                throw SampleBufferAudioWriterError.cannotAppend
            }
            guard input.isReadyForMoreMediaData else {
                throw SampleBufferAudioWriterError.inputNotReady
            }

            let retimestamped = try retimestamp(
                sampleBuffer,
                relativeTo: firstPresentationTime
            )
            guard input.append(retimestamped) else {
                throw SampleBufferAudioWriterError.cannotAppend
            }
            hasSamples = true
        }
    }

    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !isFinishing else {
                    continuation.resume(throwing: SampleBufferAudioWriterError.alreadyFinished)
                    return
                }
                isFinishing = true
                guard hasSamples, let writer, let input else {
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: SampleBufferAudioWriterError.noSamples)
                    return
                }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    queue.async { [self] in
                        guard self.writer?.status == .completed else {
                            continuation.resume(throwing: SampleBufferAudioWriterError.cannotFinish)
                            return
                        }
                        do {
                            let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
                            guard (values.fileSize ?? 0) > 0 else {
                                throw SampleBufferAudioWriterError.outputMissing
                            }
                            continuation.resume(returning: outputURL)
                        } catch let error as SampleBufferAudioWriterError {
                            continuation.resume(throwing: error)
                        } catch {
                            continuation.resume(throwing: SampleBufferAudioWriterError.outputMissing)
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        queue.sync {
            isFinishing = true
            writer?.cancelWriting()
            writer = nil
            input = nil
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    private func prepareWriter(for sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw SampleBufferAudioWriterError.invalidSampleBuffer
        }
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: outputURL)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: settings,
                sourceFormatHint: formatDescription
            )
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw SampleBufferAudioWriterError.cannotAddInput
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw SampleBufferAudioWriterError.cannotStartWriting
            }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer
            self.input = input
            firstPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        } catch let error as SampleBufferAudioWriterError {
            throw error
        } catch {
            throw SampleBufferAudioWriterError.cannotCreateWriter
        }
    }

    private func retimestamp(
        _ sampleBuffer: CMSampleBuffer,
        relativeTo firstPresentationTime: CMTime
    ) throws -> CMSampleBuffer {
        var timingCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        ) == noErr, timingCount > 0 else {
            throw SampleBufferAudioWriterError.cannotRetimestamp
        }
        var timings = Array(
            repeating: CMSampleTimingInfo.invalid,
            count: timingCount
        )
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: &timings,
            entriesNeededOut: &timingCount
        ) == noErr else {
            throw SampleBufferAudioWriterError.cannotRetimestamp
        }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isValid {
                timings[index].presentationTimeStamp = CMTimeSubtract(
                    timings[index].presentationTimeStamp,
                    firstPresentationTime
                )
            }
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = CMTimeSubtract(
                    timings[index].decodeTimeStamp,
                    firstPresentationTime
                )
            }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: &timings,
            sampleBufferOut: &copy
        ) == noErr, let copy else {
            throw SampleBufferAudioWriterError.cannotRetimestamp
        }
        return copy
    }
}
