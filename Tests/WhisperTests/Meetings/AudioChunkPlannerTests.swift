@preconcurrency import AVFoundation
import Darwin
import Foundation
import XCTest
@testable import Whisper

final class AudioChunkPlannerTests: XCTestCase {
    func testThreeHoursProducesNineTwentyMinuteChunksWithOneSecondOverlap() {
        let chunks = AudioChunkPlanner.plan(
            duration: 10_800,
            chunkDuration: 1_200,
            overlap: 1
        )

        XCTAssertEqual(chunks.count, 9)
        XCTAssertEqual(chunks.first?.start, 0)
        XCTAssertEqual(chunks.last?.end, 10_800)
        XCTAssertEqual(chunks[1].start, 1_199)
        XCTAssertEqual(chunks[1].end, 2_400)
    }

    func testPlannerRejectsInvalidDurationsAndOverlap() {
        XCTAssertTrue(AudioChunkPlanner.plan(duration: 0, chunkDuration: 1_200, overlap: 1).isEmpty)
        XCTAssertTrue(AudioChunkPlanner.plan(duration: 60, chunkDuration: 0, overlap: 1).isEmpty)
        XCTAssertTrue(AudioChunkPlanner.plan(duration: 60, chunkDuration: 60, overlap: 60).isEmpty)
        XCTAssertTrue(AudioChunkPlanner.plan(duration: 60, chunkDuration: 60, overlap: -1).isEmpty)
    }

    func testSyntheticThreeHourExportKeepsEveryChunkUnderCapWithBoundedWork() async throws {
        let fixture = try makeFixture(transientBytes: 1_048_576) { _ in 9_600_000 }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 10_800, chunkDuration: 1_200, overlap: 1)

        let chunks = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )

        XCTAssertEqual(chunks.count, 9)
        XCTAssertEqual(fixture.rangeExporter.exportCount, 9)
        XCTAssertEqual(fixture.rangeExporter.maximumConcurrentExports, 1)
        XCTAssertLessThanOrEqual(fixture.rangeExporter.maximumTransientBytes, 1_048_576)
        XCTAssertTrue(chunks.allSatisfy { $0.fileSizeBytes <= 20_000_000 })
        XCTAssertEqual(chunks.first?.startOffset, 0)
        XCTAssertEqual(chunks.last?.endOffset, 10_800)
    }

    func testOversizedRangeSplitsRecursivelyAndPersistsProgress() async throws {
        let fixture = try makeFixture { range in
            range.duration > 600 ? 21_000_000 : 10_500_000
        }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 1_200, chunkDuration: 1_200, overlap: 1)

        let chunks = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )

        XCTAssertEqual(chunks.map(\.startOffset), [0, 600])
        XCTAssertEqual(chunks.map(\.endOffset), [600, 1_200])
        XCTAssertEqual(chunks.map(\.index), [0, 1])
        XCTAssertTrue(chunks.allSatisfy { $0.fileSizeBytes <= 20_000_000 })
        let reloaded = try AudioChunkManifestStore(url: fixture.manifestURL).load()
        XCTAssertEqual(reloaded?.chunks, chunks)
    }

    func testRelaunchReusesValidChunksAndRebuildsMissingExports() async throws {
        let fixture = try makeFixture { _ in 8_000_000 }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 2_400, chunkDuration: 1_200, overlap: 1)

        let first = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )
        XCTAssertEqual(fixture.rangeExporter.exportCount, 2)

        let relaunchedStore = AudioChunkManifestStore(url: fixture.manifestURL)
        _ = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: relaunchedStore
        )
        XCTAssertEqual(fixture.rangeExporter.exportCount, 2)

        let missingURL = fixture.outputDirectory.appendingPathComponent(first[1].relativePath)
        try FileManager.default.removeItem(at: missingURL)
        let rebuilt = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: relaunchedStore
        )
        XCTAssertEqual(fixture.rangeExporter.exportCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.outputDirectory.appendingPathComponent(rebuilt[1].relativePath).path
        ))
    }

    func testMissingTranscribedChunkKeepsPersistedProgress() async throws {
        let fixture = try makeFixture { _ in 8_000_000 }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 1_200, chunkDuration: 1_200, overlap: 1)
        let first = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )
        let exported = try XCTUnwrap(first.first)
        let transcribed = AudioChunkRecord(
            source: exported.source,
            planIndex: exported.planIndex,
            index: exported.index,
            startOffset: exported.startOffset,
            endOffset: exported.endOffset,
            relativePath: exported.relativePath,
            status: .transcribed,
            retryCount: 3,
            fileSizeBytes: exported.fileSizeBytes
        )
        try fixture.store.save(AudioChunkManifest(chunks: [transcribed]))
        try FileManager.default.removeItem(
            at: fixture.outputDirectory.appendingPathComponent(transcribed.relativePath)
        )

        let resumed = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: AudioChunkManifestStore(url: fixture.manifestURL)
        )

        XCTAssertEqual(fixture.rangeExporter.exportCount, 1)
        XCTAssertEqual(resumed.first?.status, .transcribed)
        XCTAssertEqual(resumed.first?.retryCount, 3)
    }

    func testSplitRangeRebuildsOnlyMissingExportAndKeepsTranscribedSibling() async throws {
        let fixture = try makeFixture { range in
            range.duration > 600 ? 21_000_000 : 10_500_000
        }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 1_200, chunkDuration: 1_200, overlap: 1)
        let first = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )
        let firstChild = first[0]
        let secondChild = first[1]
        let transcribed = AudioChunkRecord(
            source: firstChild.source,
            planIndex: firstChild.planIndex,
            index: firstChild.index,
            startOffset: firstChild.startOffset,
            endOffset: firstChild.endOffset,
            relativePath: firstChild.relativePath,
            status: .transcribed,
            retryCount: 3,
            fileSizeBytes: firstChild.fileSizeBytes
        )
        try fixture.store.save(AudioChunkManifest(chunks: [transcribed, secondChild]))
        try FileManager.default.removeItem(
            at: fixture.outputDirectory.appendingPathComponent(firstChild.relativePath)
        )
        try FileManager.default.removeItem(
            at: fixture.outputDirectory.appendingPathComponent(secondChild.relativePath)
        )

        let resumed = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: AudioChunkManifestStore(url: fixture.manifestURL)
        )

        XCTAssertEqual(fixture.rangeExporter.exportCount, 4)
        XCTAssertEqual(resumed.first?.status, .transcribed)
        XCTAssertEqual(resumed.first?.retryCount, 3)
        XCTAssertEqual(resumed.last?.status, .exported)
    }

    func testConcurrentSourceExportsAtomicallyPreserveBothProgressSets() async throws {
        let fixture = try makeFixture { _ in 8_000_000 }
        defer { fixture.removeFiles() }
        let plan = AudioChunkPlanner.plan(duration: 1_200, chunkDuration: 1_200, overlap: 1)
        let secondStore = AudioChunkManifestStore(url: fixture.manifestURL)

        async let microphone = fixture.exporter.export(
            track: fixture.trackURL,
            source: .microphone,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )
        async let systemAudio = fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: plan,
            outputDirectory: fixture.outputDirectory,
            manifestStore: secondStore
        )
        _ = try await (microphone, systemAudio)

        let manifest = try XCTUnwrap(try fixture.store.load())
        XCTAssertEqual(Set(manifest.chunks.map(\.source)), [.microphone, .systemAudio])
    }

    func testManifestPathTraversalIsRejectedAndRebuiltInsideChunkDirectory() async throws {
        let fixture = try makeFixture { _ in 8_000_000 }
        defer { fixture.removeFiles() }
        let outside = fixture.root.appendingPathComponent("outside.m4a")
        try Data([1]).write(to: outside)
        let unsafe = AudioChunkRecord(
            source: .systemAudio,
            planIndex: 0,
            index: 0,
            startOffset: 0,
            endOffset: 1_200,
            relativePath: "../outside.m4a",
            status: .exported,
            retryCount: 0,
            fileSizeBytes: 8_000_000
        )
        try fixture.store.save(AudioChunkManifest(chunks: [unsafe]))

        let rebuilt = try await fixture.exporter.export(
            track: fixture.trackURL,
            source: .systemAudio,
            plan: AudioChunkPlanner.plan(duration: 1_200, chunkDuration: 1_200, overlap: 1),
            outputDirectory: fixture.outputDirectory,
            manifestStore: fixture.store
        )

        XCTAssertEqual(rebuilt.first?.relativePath, "systemAudio-000.m4a")
        XCTAssertEqual(try Data(contentsOf: outside), Data([1]))
    }

    func testAVAssetExporterCreatesPlayableM4AChunksForPlannedRanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperRealChunkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.m4a")
        let writer = SampleBufferAudioWriter(outputURL: sourceURL)
        for index in 0..<30 {
            try writer.append(
                makeTestAudioSampleBuffer(
                    presentationSeconds: Double(index) * 0.1,
                    amplitude: 0.25
                )
            )
        }
        _ = try await writer.finish()
        let outputDirectory = root.appendingPathComponent("chunks", isDirectory: true)
        let store = AudioChunkManifestStore(url: root.appendingPathComponent("chunks.json"))

        let chunks = try await AudioChunkExporter().export(
            track: sourceURL,
            source: .microphone,
            plan: AudioChunkPlanner.plan(duration: 2, chunkDuration: 1, overlap: 0.1),
            outputDirectory: outputDirectory,
            manifestStore: store
        )

        XCTAssertEqual(chunks.count, 2)
        for chunk in chunks {
            let url = outputDirectory.appendingPathComponent(chunk.relativePath)
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            XCTAssertGreaterThan(duration, 0.8)
            XCTAssertLessThanOrEqual(chunk.fileSizeBytes, 20_000_000)
        }
    }

    func testSyntheticThreeHourAVAssetExportHasBoundedPeakResidentMemory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperThreeHourChunkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let segmentURL = root.appendingPathComponent("segment.m4a")
        let writer = SampleBufferAudioWriter(outputURL: segmentURL)
        for index in 0..<10 {
            try writer.append(
                makeTestAudioSampleBuffer(
                    presentationSeconds: Double(index) * 0.1,
                    amplitude: 0.1
                )
            )
        }
        _ = try await writer.finish()
        let segmentAsset = AVURLAsset(url: segmentURL)
        let segmentTracks = try await segmentAsset.loadTracks(withMediaType: .audio)
        let segmentTrack = try XCTUnwrap(segmentTracks.first)
        let composition = AVMutableComposition()
        let compositionTrack = try XCTUnwrap(
            composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        let sampleRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 0.1, preferredTimescale: 600)
        )
        try compositionTrack.insertTimeRange(sampleRange, of: segmentTrack, at: .zero)
        try compositionTrack.insertTimeRange(
            sampleRange,
            of: segmentTrack,
            at: CMTime(seconds: 10_799.9, preferredTimescale: 600)
        )
        let sourceURL = root.appendingPathComponent("three-hours.mov")
        let timelineExporter = try XCTUnwrap(
            AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        )
        try await timelineExporter.export(to: sourceURL, as: .mov)
        let sourceDuration = try await AVURLAsset(url: sourceURL).load(.duration).seconds
        XCTAssertEqual(sourceDuration, 10_800, accuracy: 0.2)

        let sampler = PeakResidentMemorySampler()
        let samplingTask = sampler.start()
        let chunks = try await AudioChunkExporter().export(
            track: sourceURL,
            source: .systemAudio,
            plan: AudioChunkPlanner.plan(duration: 10_800, chunkDuration: 1_200, overlap: 1),
            outputDirectory: root.appendingPathComponent("chunks", isDirectory: true),
            manifestStore: AudioChunkManifestStore(url: root.appendingPathComponent("chunks.json"))
        )
        samplingTask.cancel()
        await samplingTask.value

        XCTAssertEqual(chunks.count, 9)
        XCTAssertTrue(chunks.allSatisfy { $0.fileSizeBytes <= 20_000_000 })
        XCTAssertLessThan(sampler.peakGrowthBytes, 64 * 1_024 * 1_024)
    }

    private func makeFixture(
        transientBytes: Int = 0,
        sizeForRange: @escaping @Sendable (AudioChunkRange) -> Int64
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperChunkTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("chunks", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let trackURL = root.appendingPathComponent("track.m4a")
        try Data([1]).write(to: trackURL)
        let manifestURL = root.appendingPathComponent("chunks.json")
        let rangeExporter = FakeAudioRangeExporter(
            transientBytes: transientBytes,
            sizeForRange: sizeForRange
        )
        let exporter = AudioChunkExporter(
            rangeExporter: rangeExporter,
            fileSize: { try rangeExporter.reportedSize(for: $0) }
        )
        return Fixture(
            root: root,
            outputDirectory: outputDirectory,
            trackURL: trackURL,
            manifestURL: manifestURL,
            rangeExporter: rangeExporter,
            exporter: exporter,
            store: AudioChunkManifestStore(url: manifestURL)
        )
    }
}

private struct Fixture {
    let root: URL
    let outputDirectory: URL
    let trackURL: URL
    let manifestURL: URL
    let rangeExporter: FakeAudioRangeExporter
    let exporter: AudioChunkExporter
    let store: AudioChunkManifestStore

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FakeAudioRangeExporter: AudioRangeExporting, @unchecked Sendable {
    private let lock = NSLock()
    private let sizeForRange: @Sendable (AudioChunkRange) -> Int64
    private var sizes: [URL: Int64] = [:]
    private var activeExports = 0
    private var activeTransientBytes = 0
    private var _exportCount = 0
    private var _maximumConcurrentExports = 0
    private var _maximumTransientBytes = 0

    private let transientBytes: Int

    init(
        transientBytes: Int,
        sizeForRange: @escaping @Sendable (AudioChunkRange) -> Int64
    ) {
        self.transientBytes = transientBytes
        self.sizeForRange = sizeForRange
    }

    var exportCount: Int { lock.withLock { _exportCount } }
    var maximumConcurrentExports: Int { lock.withLock { _maximumConcurrentExports } }
    var maximumTransientBytes: Int { lock.withLock { _maximumTransientBytes } }

    func export(track: URL, range: AudioChunkRange, outputURL: URL) async throws {
        let payload = transientBytes > 0
            ? Data(repeating: 1, count: transientBytes)
            : Data([1])
        lock.withLock {
            _exportCount += 1
            activeExports += 1
            activeTransientBytes += payload.count
            _maximumConcurrentExports = max(_maximumConcurrentExports, activeExports)
            _maximumTransientBytes = max(_maximumTransientBytes, activeTransientBytes)
        }
        defer {
            lock.withLock {
                activeExports -= 1
                activeTransientBytes -= payload.count
            }
        }
        await Task.yield()
        try payload.write(to: outputURL)
        lock.withLock { sizes[outputURL] = sizeForRange(range) }
    }

    func reportedSize(for url: URL) throws -> Int64 {
        try lock.withLock {
            guard let size = sizes[url] else { throw FakeExporterError.missingSize }
            return size
        }
    }
}

private enum FakeExporterError: Error {
    case missingSize
}

private final class PeakResidentMemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private let baselineBytes = currentResidentMemoryBytes()
    private var peakBytes = currentResidentMemoryBytes()

    var peakGrowthBytes: UInt64 {
        lock.withLock { peakBytes > baselineBytes ? peakBytes - baselineBytes : 0 }
    }

    func start() -> Task<Void, Never> {
        Task.detached { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .milliseconds(1))
            }
            self?.sample()
        }
    }

    private func sample() {
        let current = Self.currentResidentMemoryBytes()
        lock.withLock { peakBytes = max(peakBytes, current) }
    }

    private static func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}
