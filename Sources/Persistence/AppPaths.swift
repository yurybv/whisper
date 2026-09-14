import Foundation

struct AppPaths: @unchecked Sendable {
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

    func relativeRecordingPath(for fileURL: URL) throws -> String {
        let root = recordingsURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(prefix) else { throw PersistenceError.unsafePath }
        let relativePath = String(resolved.path.dropFirst(prefix.count))
        guard relativePath.split(separator: "/").first?.hasPrefix("meeting-") == true else {
            throw PersistenceError.unsafePath
        }
        return relativePath
    }

    func relativeRecordingPath(for fileURL: URL, meetingID: UUID) throws -> String {
        let relativePath = try relativeRecordingPath(for: fileURL)
        guard relativePath.split(separator: "/").first
            == Substring("meeting-\(meetingID.uuidString)") else {
            throw PersistenceError.unsafePath
        }
        return relativePath
    }

    func recordingFileURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw PersistenceError.unsafePath
        }
        let candidate = recordingsURL.appendingPathComponent(relativePath)
        _ = try relativeRecordingPath(for: candidate)
        return candidate.standardizedFileURL.resolvingSymlinksInPath()
    }

    func recordingFileURL(relativePath: String, meetingID: UUID) throws -> URL {
        let url = try recordingFileURL(relativePath: relativePath)
        _ = try relativeRecordingPath(for: url, meetingID: meetingID)
        return url
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
