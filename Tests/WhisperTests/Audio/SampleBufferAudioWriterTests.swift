@preconcurrency import AVFoundation
import AudioToolbox
@preconcurrency import CoreMedia
import XCTest
@testable import Whisper

final class SampleBufferAudioWriterTests: XCTestCase {
    func testWritesRetimestampedPlayableMonoAACFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("track.m4a")
        let writer = SampleBufferAudioWriter(outputURL: outputURL)

        for index in 0..<20 {
            try writer.append(
                makeTestAudioSampleBuffer(
                    presentationSeconds: 10 + (Double(index) * 0.1),
                    amplitude: index.isMultiple(of: 2) ? 0.2 : 0.4
                )
            )
        }
        let finalizedURL = try await writer.finish()

        XCTAssertEqual(finalizedURL, outputURL)
        XCTAssertGreaterThan(try Data(contentsOf: outputURL).count, 0)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let formatDescriptions = try await XCTUnwrap(audioTracks.first).load(.formatDescriptions)
        let description = try XCTUnwrap(formatDescriptions.first)
        let streamDescription = try XCTUnwrap(
            CMAudioFormatDescriptionGetStreamBasicDescription(description)
        ).pointee

        XCTAssertEqual(duration, 2, accuracy: 0.03)
        XCTAssertEqual(streamDescription.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(streamDescription.mSampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(streamDescription.mChannelsPerFrame, 1)
        let estimatedDataRate = try await XCTUnwrap(audioTracks.first).load(.estimatedDataRate)
        XCTAssertEqual(estimatedDataRate, 64_000, accuracy: 8_000)
    }

    func testFinishRejectsTrackWithoutSamples() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperEmptyWriter-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let writer = SampleBufferAudioWriter(outputURL: outputURL)

        do {
            _ = try await writer.finish()
            XCTFail("Expected empty track failure")
        } catch {
            XCTAssertEqual(error as? SampleBufferAudioWriterError, .noSamples)
        }
    }

}
