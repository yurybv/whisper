@preconcurrency import AVFoundation
import Foundation

struct PreparedMeetingChunk: Sendable, Equatable {
    let key: String
    let source: MeetingAudioSource
    let index: Int
    let timelineStartOffset: TimeInterval
    let fileURL: URL
    let manifestURL: URL?
    let record: AudioChunkRecord?

    init(
        key: String,
        source: MeetingAudioSource,
        index: Int,
        timelineStartOffset: TimeInterval,
        fileURL: URL,
        manifestURL: URL? = nil,
        record: AudioChunkRecord? = nil
    ) {
        self.key = key
        self.source = source
        self.index = index
        self.timelineStartOffset = timelineStartOffset
        self.fileURL = fileURL
        self.manifestURL = manifestURL
        self.record = record
    }
}

protocol MeetingChunkPreparing: Sendable {
    func prepare(meeting: MeetingSnapshot) async throws -> [PreparedMeetingChunk]
    func markTranscribed(_ chunk: PreparedMeetingChunk) async throws
    func markFailed(_ chunk: PreparedMeetingChunk) async throws
}

protocol MeetingDiarizedTranscribing: Sendable {
    func transcribeDiarized(fileURL: URL) async throws -> DiarizedTranscriptionResponse
}

extension OpenAIClient: MeetingDiarizedTranscribing {}

struct PersistedDiarizedChunk: Codable, Sendable, Equatable {
    let key: String
    let source: MeetingAudioSource
    let startOffset: TimeInterval
    let response: DiarizedTranscriptionResponse
}

final class DiarizedChunkResultStore: @unchecked Sendable {
    private struct Document: Codable {
        var chunks: [PersistedDiarizedChunk]
    }

    private static let lock = NSLock()
    private let paths: AppPaths

    init(paths: AppPaths) { self.paths = paths }

    func load(meetingID: UUID) throws -> [PersistedDiarizedChunk] {
        try Self.lock.withLock {
            let url = try storeURL(meetingID: meetingID, createDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            return document.chunks.sorted(by: Self.order)
        }
    }

    func save(_ chunk: PersistedDiarizedChunk, meetingID: UUID) throws {
        try Self.lock.withLock {
            let url = try storeURL(meetingID: meetingID, createDirectory: true)
            var chunks: [PersistedDiarizedChunk] = []
            if FileManager.default.fileExists(atPath: url.path) {
                chunks = try JSONDecoder().decode(
                    Document.self,
                    from: Data(contentsOf: url)
                ).chunks
            }
            chunks.removeAll { $0.key == chunk.key }
            chunks.append(chunk)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Document(chunks: chunks.sorted(by: Self.order)))
                .write(to: url, options: .atomic)
        }
    }

    private func storeURL(meetingID: UUID, createDirectory: Bool) throws -> URL {
        let meetingDirectory = try paths.recordingDirectory(for: meetingID, create: createDirectory)
        let directory = meetingDirectory.appendingPathComponent("chunks", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("transcripts.json")
    }

    private static func order(_ lhs: PersistedDiarizedChunk, _ rhs: PersistedDiarizedChunk) -> Bool {
        if lhs.startOffset != rhs.startOffset { return lhs.startOffset < rhs.startOffset }
        if lhs.source != rhs.source { return lhs.source == .microphone }
        return lhs.key < rhs.key
    }
}

struct MeetingTranscriber: MeetingTranscribing, Sendable {
    private let client: any MeetingDiarizedTranscribing
    private let chunkPreparer: any MeetingChunkPreparing
    private let resultStore: DiarizedChunkResultStore
    private let merger: TranscriptMerger

    init(
        client: any MeetingDiarizedTranscribing,
        chunkPreparer: any MeetingChunkPreparing,
        resultStore: DiarizedChunkResultStore,
        merger: TranscriptMerger = TranscriptMerger()
    ) {
        self.client = client
        self.chunkPreparer = chunkPreparer
        self.resultStore = resultStore
        self.merger = merger
    }

    func transcribe(
        meeting: MeetingSnapshot,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> [TranscriptSegment] {
        let chunks = try await chunkPreparer.prepare(meeting: meeting)
            .sorted(by: Self.chunkOrder)
        var persisted = Dictionary(
            uniqueKeysWithValues: try resultStore.load(meetingID: meeting.id).map { ($0.key, $0) }
        )
        var completed = chunks.reduce(into: 0) { count, chunk in
            if persisted[chunk.key] != nil { count += 1 }
        }
        for chunk in chunks where persisted[chunk.key] != nil {
            try? await chunkPreparer.markTranscribed(chunk)
        }
        await progress(completed, chunks.count)

        let pending = chunks.filter { persisted[$0.key] == nil }
        var batchStart = 0
        while batchStart < pending.count {
            let batch = Array(pending[batchStart..<min(batchStart + 2, pending.count)])
            let attempts = await withTaskGroup(of: ChunkAttempt.self) { group in
                for chunk in batch {
                    group.addTask {
                        do {
                            return .success(
                                chunk,
                                try await client.transcribeDiarized(fileURL: chunk.fileURL)
                            )
                        } catch {
                            return .failure(chunk, error)
                        }
                    }
                }
                var values: [ChunkAttempt] = []
                for await attempt in group { values.append(attempt) }
                return values
            }

            var firstFailure: Error?
            for attempt in attempts {
                switch attempt {
                case let .success(chunk, response):
                    let result = PersistedDiarizedChunk(
                        key: chunk.key,
                        source: chunk.source,
                        startOffset: chunk.timelineStartOffset,
                        response: response
                    )
                    try resultStore.save(result, meetingID: meeting.id)
                    persisted[chunk.key] = result
                    try? await chunkPreparer.markTranscribed(chunk)
                    completed += 1
                    await progress(completed, chunks.count)
                case let .failure(chunk, error):
                    try? await chunkPreparer.markFailed(chunk)
                    if firstFailure == nil { firstFailure = error }
                }
            }
            if let firstFailure { throw firstFailure }
            batchStart += batch.count
        }

        let transcripts = try chunks.map { chunk -> DiarizedChunkTranscript in
            guard let result = persisted[chunk.key] else {
                throw OpenAIClientError.invalidResponse
            }
            return DiarizedChunkTranscript(
                source: result.source,
                startOffset: result.startOffset,
                response: result.response
            )
        }
        return try merger.merge(meetingID: meeting.id, chunks: transcripts)
    }

    private static func chunkOrder(_ lhs: PreparedMeetingChunk, _ rhs: PreparedMeetingChunk) -> Bool {
        if lhs.timelineStartOffset != rhs.timelineStartOffset {
            return lhs.timelineStartOffset < rhs.timelineStartOffset
        }
        if lhs.source != rhs.source { return lhs.source == .microphone }
        return lhs.index < rhs.index
    }
}

private enum ChunkAttempt: @unchecked Sendable {
    case success(PreparedMeetingChunk, DiarizedTranscriptionResponse)
    case failure(PreparedMeetingChunk, Error)
}

struct AVAssetMeetingChunkPreparer: MeetingChunkPreparing, @unchecked Sendable {
    private let paths: AppPaths
    private let exporter: AudioChunkExporter

    init(paths: AppPaths, exporter: AudioChunkExporter = AudioChunkExporter()) {
        self.paths = paths
        self.exporter = exporter
    }

    func prepare(meeting: MeetingSnapshot) async throws -> [PreparedMeetingChunk] {
        var chunks: [PreparedMeetingChunk] = []
        chunks += try await prepare(
            source: .microphone,
            relativeTrackPath: meeting.microphoneRelativePath,
            sourceOffset: meeting.microphoneStartOffset,
            meetingID: meeting.id
        )
        chunks += try await prepare(
            source: .systemAudio,
            relativeTrackPath: meeting.systemAudioRelativePath,
            sourceOffset: meeting.systemAudioStartOffset,
            meetingID: meeting.id
        )
        return chunks
    }

    func markTranscribed(_ chunk: PreparedMeetingChunk) async throws {
        try update(chunk, status: .transcribed, retryIncrement: 0)
        if FileManager.default.fileExists(atPath: chunk.fileURL.path) {
            try FileManager.default.removeItem(at: chunk.fileURL)
        }
    }

    func markFailed(_ chunk: PreparedMeetingChunk) async throws {
        try update(chunk, status: .failed, retryIncrement: 1)
    }

    private func prepare(
        source: MeetingAudioSource,
        relativeTrackPath: String,
        sourceOffset: TimeInterval,
        meetingID: UUID
    ) async throws -> [PreparedMeetingChunk] {
        guard !relativeTrackPath.isEmpty else { return [] }
        let trackURL = try paths.recordingFileURL(
            relativePath: relativeTrackPath,
            meetingID: meetingID
        )
        let duration = try await AVURLAsset(url: trackURL).load(.duration).seconds
        let meetingDirectory = try paths.recordingDirectory(for: meetingID)
        let outputDirectory = meetingDirectory.appendingPathComponent("chunks", isDirectory: true)
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        let records = try await exporter.export(
            track: trackURL,
            source: source,
            plan: AudioChunkPlanner.plan(duration: duration),
            outputDirectory: outputDirectory,
            manifestStore: AudioChunkManifestStore(url: manifestURL)
        )
        return records.map { record in
            PreparedMeetingChunk(
                key: "\(source.rawValue):\(record.relativePath)",
                source: source,
                index: record.index,
                timelineStartOffset: sourceOffset + record.startOffset,
                fileURL: outputDirectory.appendingPathComponent(record.relativePath),
                manifestURL: manifestURL,
                record: record
            )
        }
    }

    private func update(
        _ chunk: PreparedMeetingChunk,
        status: AudioChunkStatus,
        retryIncrement: Int
    ) throws {
        guard let manifestURL = chunk.manifestURL, let record = chunk.record else { return }
        _ = try AudioChunkManifestStore(url: manifestURL).update { manifest in
            guard let index = manifest.chunks.firstIndex(where: {
                $0.source == record.source && $0.relativePath == record.relativePath
            }) else { return }
            let current = manifest.chunks[index]
            manifest.chunks[index] = AudioChunkRecord(
                source: current.source,
                planIndex: current.planIndex,
                index: current.index,
                startOffset: current.startOffset,
                endOffset: current.endOffset,
                relativePath: current.relativePath,
                status: status,
                retryCount: current.retryCount + retryIncrement,
                fileSizeBytes: current.fileSizeBytes
            )
        }
    }
}
