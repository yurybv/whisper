import Foundation

struct AppPaths {
    let rootURL: URL
    let recordingsURL: URL
    let temporaryURL: URL

    private let fileManager: FileManager

    init(fileManager: FileManager = .default, rootURL: URL? = nil) throws {
        self.fileManager = fileManager

        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw PersistenceError.applicationSupportUnavailable
            }
            self.rootURL = applicationSupport
                .appendingPathComponent("Whisper", isDirectory: true)
                .standardizedFileURL
        }

        recordingsURL = self.rootURL.appendingPathComponent("Recordings", isDirectory: true)
        temporaryURL = self.rootURL.appendingPathComponent("Temporary", isDirectory: true)

        try fileManager.createDirectory(
            at: recordingsURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: true
        )
    }

    func recordingDirectory(for meetingID: UUID, create: Bool = true) throws -> URL {
        let candidate = recordingsURL.appendingPathComponent(
            "meeting-\(meetingID.uuidString)",
            isDirectory: true
        )
        let safeURL = try validatedMeetingDirectory(candidate)
        if create {
            try fileManager.createDirectory(at: safeURL, withIntermediateDirectories: true)
        }
        return safeURL
    }

    func deleteRecordingDirectory(for meetingID: UUID) throws {
        try deleteRecordingDirectory(at: recordingDirectory(for: meetingID, create: false))
    }

    func deleteRecordingDirectory(at candidate: URL) throws {
        let safeURL = try validatedMeetingDirectory(candidate)
        guard fileManager.fileExists(atPath: safeURL.path) else {
            return
        }
        try fileManager.removeItem(at: safeURL)
    }

    private func validatedMeetingDirectory(_ candidate: URL) throws -> URL {
        let root = recordingsURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard
            resolved != root,
            resolved.deletingLastPathComponent() == root,
            resolved.lastPathComponent.hasPrefix("meeting-")
        else {
            throw PersistenceError.unsafePath
        }
        return URL(fileURLWithPath: resolved.path, isDirectory: true)
    }
}
