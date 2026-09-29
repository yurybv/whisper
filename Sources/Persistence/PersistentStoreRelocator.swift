import CoreData
import Darwin
import Foundation
import SwiftData

@MainActor
protocol PersistentStoreRelocating {
    func prepareCanonicalStore(paths: AppPaths, legacyStoreURL: URL) throws -> URL
}

@MainActor
final class PersistentStoreRelocator: PersistentStoreRelocating {
    typealias SnapshotStore = (URL, URL) throws -> Void
    typealias MetadataReader = (URL) throws -> [String: Data]
    typealias RemoveEmptyDirectory = (URL) throws -> Void

    private static let requiredEntityNames: Set<String> = [
        "ModeEntity",
        "DictationEntity",
        "MeetingEntity",
        "TranscriptSegmentEntity",
        "RecordingCleanupEntity",
    ]

    private let fileManager: FileManager
    private let snapshotStore: SnapshotStore
    private let metadataReader: MetadataReader
    private let removeEmptyDirectory: RemoveEmptyDirectory

    init(
        fileManager: FileManager = .default,
        snapshotStore: SnapshotStore? = nil,
        metadataReader: MetadataReader? = nil,
        removeEmptyDirectory: RemoveEmptyDirectory? = nil
    ) {
        self.fileManager = fileManager
        self.snapshotStore = snapshotStore ?? SQLiteStoreSnapshotter().snapshotStore(from:to:)
        self.metadataReader = metadataReader ?? Self.readModelVersionHashes
        self.removeEmptyDirectory = removeEmptyDirectory ?? Self.removeEmptyDirectoryAtomically
    }

    func prepareCanonicalStore(paths: AppPaths, legacyStoreURL: URL) throws -> URL {
        let canonicalURL = paths.metadataStoreURL
        guard !fileManager.fileExists(atPath: canonicalURL.path) else {
            return canonicalURL
        }
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return canonicalURL
        }
        let isCompatible: Bool
        do {
            isCompatible = try isCompatibleWhisperStore(
                at: legacyStoreURL,
                paths: paths
            )
        } catch {
            throw PersistenceError.metadataMigrationFailed
        }
        guard isCompatible else {
            return canonicalURL
        }

        let stagingDirectory = paths.rootURL.appendingPathComponent(
            ".MetadataMigration-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let stagedStoreURL = stagingDirectory.appendingPathComponent("Whisper.store")
            try snapshotStore(legacyStoreURL, stagedStoreURL)
            try validateStore(at: stagedStoreURL)

            if fileManager.fileExists(atPath: canonicalURL.path) {
                try fileManager.removeItem(at: stagingDirectory)
                return canonicalURL
            }

            do {
                try removeEmptyDirectory(paths.metadataDirectoryURL)
                try fileManager.moveItem(at: stagingDirectory, to: paths.metadataDirectoryURL)
            } catch {
                if fileManager.fileExists(atPath: canonicalURL.path) {
                    try? fileManager.removeItem(at: stagingDirectory)
                    return canonicalURL
                }
                throw error
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: paths.metadataDirectoryURL.path
            )
            return canonicalURL
        } catch {
            if fileManager.fileExists(atPath: stagingDirectory.path) {
                try? fileManager.removeItem(at: stagingDirectory)
            }
            throw PersistenceError.metadataMigrationFailed
        }
    }

    private func isCompatibleWhisperStore(at storeURL: URL, paths: AppPaths) throws -> Bool {
        let legacyHashes = try metadataReader(storeURL)
        let currentHashes = try currentModelVersionHashes(paths: paths)
        guard Set(currentHashes.keys) == Self.requiredEntityNames else {
            throw PersistenceError.metadataMigrationFailed
        }
        return legacyHashes == currentHashes
    }

    private func currentModelVersionHashes(paths: AppPaths) throws -> [String: Data] {
        let probeDirectory = paths.rootURL.appendingPathComponent(
            ".MetadataModelProbe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: probeDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: probeDirectory) }

        let probeStoreURL = probeDirectory.appendingPathComponent("Whisper.store")
        let controller = try PersistenceController(storeURL: probeStoreURL)
        return try withExtendedLifetime(controller) {
            try metadataReader(probeStoreURL)
        }
    }

    private static func readModelVersionHashes(at storeURL: URL) throws -> [String: Data] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL
        )
        return metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
    }

    private func validateStore(at storeURL: URL) throws {
        let controller = try PersistenceController(storeURL: storeURL)
        let context = controller.container.mainContext
        _ = try context.fetchCount(FetchDescriptor<ModeEntity>())
        _ = try context.fetchCount(FetchDescriptor<DictationEntity>())
        _ = try context.fetchCount(FetchDescriptor<MeetingEntity>())
        _ = try context.fetchCount(FetchDescriptor<TranscriptSegmentEntity>())
        _ = try context.fetchCount(FetchDescriptor<RecordingCleanupEntity>())
    }

    private static func removeEmptyDirectoryAtomically(at directoryURL: URL) throws {
        let errorCode = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return EINVAL }
            return Darwin.rmdir(path) == 0 ? 0 : errno
        }
        guard errorCode == 0 || errorCode == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
    }
}
