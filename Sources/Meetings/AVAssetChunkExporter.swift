@preconcurrency import AVFoundation
import Foundation

protocol AudioRangeExporting: Sendable {
    func export(track: URL, range: AudioChunkRange, outputURL: URL) async throws
}

enum AudioChunkExporterError: Error, Sendable, Equatable {
    case invalidPlan
    case outputMissing
    case cannotMeetSizeLimit
    case exportFailed
}

struct AudioChunkExporter: Sendable {
    static let uploadSizeLimitBytes: Int64 = 20_000_000
    static let minimumSplitDuration: TimeInterval = 1

    private let rangeExporter: any AudioRangeExporting
    private let fileSize: @Sendable (URL) throws -> Int64

    init(
        rangeExporter: any AudioRangeExporting = AVAssetRangeExporter(),
        fileSize: @escaping @Sendable (URL) throws -> Int64 = {
            let values = try $0.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                throw AudioChunkExporterError.outputMissing
            }
            return Int64(size)
        }
    ) {
        self.rangeExporter = rangeExporter
        self.fileSize = fileSize
    }

    func export(
        track: URL,
        source: MeetingAudioSource,
        plan: [AudioChunkRange],
        outputDirectory: URL,
        manifestStore: AudioChunkManifestStore
    ) async throws -> [AudioChunkRecord] {
        guard !plan.isEmpty,
              plan.allSatisfy({ $0.duration > 0 }) else {
            throw AudioChunkExporterError.invalidPlan
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        var manifest = try manifestStore.load() ?? AudioChunkManifest(chunks: [])
        let plannedIndices = Set(plan.map(\.index))

        for range in plan {
            let existing = manifest.chunks
                .filter { $0.source == source && $0.planIndex == range.index }
                .sorted { $0.startOffset < $1.startOffset }
            let exported: [AudioChunkRecord]
            if hasCompleteCoverage(
                existing,
                for: range,
                outputDirectory: outputDirectory
            ) {
                var recovered: [AudioChunkRecord] = []
                var rebuiltAny = false
                for record in existing {
                    if record.status == .transcribed
                        || isReusableExport(record, outputDirectory: outputDirectory) {
                        recovered.append(record)
                        continue
                    }
                    rebuiltAny = true
                    let missingRange = AudioChunkRange(
                        index: range.index,
                        start: record.startOffset,
                        end: record.endOffset
                    )
                    recovered.append(
                        contentsOf: try await exportRecursively(
                            track: track,
                            source: source,
                            range: missingRange,
                            planIndex: range.index,
                            pathSuffix: "-at-\(Self.millisecondKey(record.startOffset))",
                            outputDirectory: outputDirectory
                        )
                    )
                }
                guard rebuiltAny else { continue }
                exported = recovered
            } else {
                exported = try await exportRecursively(
                    track: track,
                    source: source,
                    range: range,
                    planIndex: range.index,
                    pathSuffix: "",
                    outputDirectory: outputDirectory
                )
            }
            manifest.chunks.removeAll {
                $0.source == source && $0.planIndex == range.index
            }
            manifest.chunks.append(contentsOf: exported)
            normalizeIndices(in: &manifest, source: source)
            manifest = try manifestStore.update { latest in
                latest.chunks.removeAll {
                    $0.source == source
                        && ($0.planIndex == range.index
                            || !plannedIndices.contains($0.planIndex))
                }
                latest.chunks.append(contentsOf: exported)
                normalizeIndices(in: &latest, source: source)
            }
        }

        manifest = try manifestStore.update { latest in
            latest.chunks.removeAll {
                $0.source == source && !plannedIndices.contains($0.planIndex)
            }
            normalizeIndices(in: &latest, source: source)
        }
        return manifest.chunks
            .filter { $0.source == source }
            .sorted { $0.index < $1.index }
    }

    private func exportRecursively(
        track: URL,
        source: MeetingAudioSource,
        range: AudioChunkRange,
        planIndex: Int,
        pathSuffix: String,
        outputDirectory: URL
    ) async throws -> [AudioChunkRecord] {
        let filename = "\(source.rawValue)-\(String(format: "%03d", planIndex))\(pathSuffix).m4a"
        let outputURL = outputDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        do {
            try await rangeExporter.export(track: track, range: range, outputURL: outputURL)
        } catch {
            throw AudioChunkExporterError.exportFailed
        }
        let outputSize = try fileSize(outputURL)
        guard outputSize > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioChunkExporterError.outputMissing
        }
        if outputSize <= Self.uploadSizeLimitBytes {
            return [
                AudioChunkRecord(
                    source: source,
                    planIndex: planIndex,
                    index: 0,
                    startOffset: range.start,
                    endOffset: range.end,
                    relativePath: filename,
                    status: .exported,
                    retryCount: 0,
                    fileSizeBytes: outputSize
                )
            ]
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard range.duration > Self.minimumSplitDuration else {
            throw AudioChunkExporterError.cannotMeetSizeLimit
        }
        let midpoint = range.start + (range.duration / 2)
        let left = AudioChunkRange(index: range.index, start: range.start, end: midpoint)
        let right = AudioChunkRange(index: range.index, start: midpoint, end: range.end)
        let leftRecords = try await exportRecursively(
            track: track,
            source: source,
            range: left,
            planIndex: planIndex,
            pathSuffix: pathSuffix + "-0",
            outputDirectory: outputDirectory
        )
        let rightRecords = try await exportRecursively(
            track: track,
            source: source,
            range: right,
            planIndex: planIndex,
            pathSuffix: pathSuffix + "-1",
            outputDirectory: outputDirectory
        )
        return leftRecords + rightRecords
    }

    private func hasCompleteCoverage(
        _ records: [AudioChunkRecord],
        for range: AudioChunkRange,
        outputDirectory: URL
    ) -> Bool {
        guard let first = records.first,
              let last = records.last,
              first.startOffset == range.start,
              last.endOffset == range.end else {
            return false
        }
        for (index, record) in records.enumerated() {
            if index > 0, records[index - 1].endOffset != record.startOffset {
                return false
            }
            guard validatedChunkURL(
                relativePath: record.relativePath,
                outputDirectory: outputDirectory
            ) != nil else {
                return false
            }
        }
        return true
    }

    private func isReusableExport(
        _ record: AudioChunkRecord,
        outputDirectory: URL
    ) -> Bool {
        guard record.status == .exported,
              let url = validatedChunkURL(
                relativePath: record.relativePath,
                outputDirectory: outputDirectory
              ),
              FileManager.default.fileExists(atPath: url.path),
              let persistedSize = try? fileSize(url) else {
            return false
        }
        return persistedSize > 0 && persistedSize <= Self.uploadSizeLimitBytes
    }

    private static func millisecondKey(_ time: TimeInterval) -> Int64 {
        Int64((time * 1_000).rounded())
    }

    private func validatedChunkURL(
        relativePath: String,
        outputDirectory: URL
    ) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/") else { return nil }
        let root = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.deletingLastPathComponent() == root else { return nil }
        return candidate
    }

    private func normalizeIndices(
        in manifest: inout AudioChunkManifest,
        source: MeetingAudioSource
    ) {
        let otherSources = manifest.chunks.filter { $0.source != source }
        let normalized = manifest.chunks
            .filter { $0.source == source }
            .sorted {
                ($0.startOffset, $0.endOffset, $0.relativePath)
                    < ($1.startOffset, $1.endOffset, $1.relativePath)
            }
            .enumerated()
            .map { $0.element.reindexed($0.offset) }
        manifest.chunks = otherSources + normalized
    }
}

final class AVAssetRangeExporter: AudioRangeExporting, @unchecked Sendable {
    func export(track: URL, range: AudioChunkRange, outputURL: URL) async throws {
        let asset = AVURLAsset(url: track)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioChunkExporterError.exportFailed
        }
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )
        do {
            try await exporter.export(to: outputURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioChunkExporterError.exportFailed
        }
    }
}
