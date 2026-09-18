import CoreData
import Foundation
import SwiftData

@MainActor
protocol PersistentStoreRelocating {
    func prepareCanonicalStore(paths: AppPaths, legacyStoreURL: URL) throws -> URL
}

@MainActor
final class PersistentStoreRelocator: PersistentStoreRelocating {
    typealias CopyItem = (URL, URL) throws -> Void

    private static let requiredEntityNames: Set<String> = [
        "ModeEntity",
        "DictationEntity",
        "MeetingEntity",
        "TranscriptSegmentEntity",
        "RecordingCleanupEntity",
    ]

    private let fileManager: FileManager
    private let copyItem: CopyItem

    init(
        fileManager: FileManager = .default,
        copyItem: CopyItem? = nil
    ) {
        self.fileManager = fileManager
        self.copyItem = copyItem ?? fileManager.copyItem(at:to:)
    }

    func prepareCanonicalStore(paths: AppPaths, legacyStoreURL: URL) throws -> URL {
        let canonicalURL = paths.metadataStoreURL
        guard !fileManager.fileExists(atPath: canonicalURL.path) else {
            return canonicalURL
        }
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return canonicalURL
        }
        guard isCompatibleWhisperStore(at: legacyStoreURL) else {
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
            try copyStoreFamily(from: legacyStoreURL, to: stagedStoreURL)
            try validateStore(at: stagedStoreURL)

            if fileManager.fileExists(atPath: canonicalURL.path) {
                try fileManager.removeItem(at: stagingDirectory)
                return canonicalURL
            }

            try removeEmptyMetadataDirectory(at: paths.metadataDirectoryURL)
            try fileManager.moveItem(at: stagingDirectory, to: paths.metadataDirectoryURL)
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

    private func isCompatibleWhisperStore(at storeURL: URL) -> Bool {
        guard
            let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL
            ),
            let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data]
        else {
            return false
        }
        return Set(hashes.keys) == Self.requiredEntityNames
    }

    private func copyStoreFamily(from source: URL, to destination: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceMember = URL(fileURLWithPath: source.path + suffix)
            guard fileManager.fileExists(atPath: sourceMember.path) else { continue }
            let destinationMember = URL(fileURLWithPath: destination.path + suffix)
            try copyItem(sourceMember, destinationMember)
        }
    }

    private func validateStore(at storeURL: URL) throws {
        let controller = try PersistenceController(storeURL: storeURL)
        let context = controller.container.mainContext
        _ = try context.fetch(FetchDescriptor<ModeEntity>()).count
        _ = try context.fetch(FetchDescriptor<DictationEntity>()).count
        _ = try context.fetch(FetchDescriptor<MeetingEntity>()).count
        _ = try context.fetch(FetchDescriptor<TranscriptSegmentEntity>()).count
        _ = try context.fetch(FetchDescriptor<RecordingCleanupEntity>()).count
    }

    private func removeEmptyMetadataDirectory(at directoryURL: URL) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        guard contents.isEmpty else {
            throw PersistenceError.metadataMigrationFailed
        }
        try fileManager.removeItem(at: directoryURL)
    }
}
