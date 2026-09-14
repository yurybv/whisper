import Foundation

enum AudioChunkStatus: String, Sendable, Codable, Equatable {
    case exported
    case transcribed
    case failed
}

struct AudioChunkRecord: Sendable, Codable, Equatable, Identifiable {
    var id: String { "\(source.rawValue)-\(index)" }

    let source: MeetingAudioSource
    let planIndex: Int
    let index: Int
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let relativePath: String
    let status: AudioChunkStatus
    let retryCount: Int
    let fileSizeBytes: Int64

    func reindexed(_ index: Int) -> AudioChunkRecord {
        AudioChunkRecord(
            source: source,
            planIndex: planIndex,
            index: index,
            startOffset: startOffset,
            endOffset: endOffset,
            relativePath: relativePath,
            status: status,
            retryCount: retryCount,
            fileSizeBytes: fileSizeBytes
        )
    }
}

struct AudioChunkManifest: Sendable, Codable, Equatable {
    var chunks: [AudioChunkRecord]
}

enum AudioChunkManifestStoreError: Error, Sendable, Equatable {
    case invalidManifest
    case cannotPersist
}

final class AudioChunkManifestStore: @unchecked Sendable {
    let url: URL
    private static let sharedLock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func load() throws -> AudioChunkManifest? {
        try Self.sharedLock.withLock { try loadUnlocked() }
    }

    func save(_ manifest: AudioChunkManifest) throws {
        try Self.sharedLock.withLock { try saveUnlocked(manifest) }
    }

    func update(
        _ transform: (inout AudioChunkManifest) throws -> Void
    ) throws -> AudioChunkManifest {
        try Self.sharedLock.withLock {
            var manifest = try loadUnlocked() ?? AudioChunkManifest(chunks: [])
            try transform(&manifest)
            try saveUnlocked(manifest)
            return manifest
        }
    }

    private func loadUnlocked() throws -> AudioChunkManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(
                AudioChunkManifest.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw AudioChunkManifestStoreError.invalidManifest
        }
    }

    private func saveUnlocked(_ manifest: AudioChunkManifest) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(to: url, options: .atomic)
        } catch {
            throw AudioChunkManifestStoreError.cannotPersist
        }
    }
}
