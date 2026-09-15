import Foundation
import SwiftData
import XCTest
@testable import Whisper

@MainActor
final class RetentionServiceTests: XCTestCase {
    func testRepositoryDeletesOnlySelectedMeetingDirectoryAndClearsTombstone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperOwnedDeletion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try AppPaths(rootURL: root)
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext, appPaths: paths)
        let selectedID = try repository.createMeeting(
            MeetingDraft(title: "Selected", status: .ready, instructionsSnapshot: "Notes")
        )
        let retainedID = try repository.createMeeting(
            MeetingDraft(title: "Retained", status: .ready, instructionsSnapshot: "Notes")
        )
        let selectedDirectory = try paths.recordingDirectory(for: selectedID)
        let retainedDirectory = try paths.recordingDirectory(for: retainedID)
        try Data("audio".utf8).write(to: selectedDirectory.appendingPathComponent("microphone.m4a"))

        try repository.deleteMeeting(id: selectedID)

        XCTAssertNil(try repository.meeting(id: selectedID))
        XCTAssertNotNil(try repository.meeting(id: retainedID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDirectory.path))
        XCTAssertTrue(try pendingCleanup(in: controller).isEmpty)
    }

    func testForeverRetriesTombstonesWithoutDeletingHistory() throws {
        let controller = try PersistenceController(inMemory: true)
        let cleaner = RecordingCleanerSpy()
        cleaner.shouldFail = true
        let repository = HistoryRepository(
            context: controller.container.mainContext,
            recordingDirectoryCleaner: cleaner
        )
        let deletedID = try repository.createMeeting(
            MeetingDraft(title: "Delete", status: .ready, instructionsSnapshot: "Notes")
        )
        let retainedReadyID = try repository.createMeeting(
            MeetingDraft(title: "Keep", status: .ready, instructionsSnapshot: "Notes")
        )
        let activeID = try repository.createMeeting(
            MeetingDraft(title: "Active", status: .recording, instructionsSnapshot: "Notes")
        )
        try repository.deleteMeeting(id: deletedID)

        let report = try RetentionService(repository: repository).perform(policy: .forever)

        XCTAssertEqual(report.pendingFileCleanup, 1)
        XCTAssertNotNil(try repository.meeting(id: retainedReadyID))
        XCTAssertNotNil(try repository.meeting(id: activeID))
        XCTAssertNil(try repository.meeting(id: deletedID))
    }

    func testManualMeetingDeleteCreatesDurableCleanupAndRetriesAfterFailure() throws {
        let controller = try PersistenceController(inMemory: true)
        let cleaner = RecordingCleanerSpy()
        cleaner.shouldFail = true
        let repository = HistoryRepository(
            context: controller.container.mainContext,
            recordingDirectoryCleaner: cleaner
        )
        let selectedID = try repository.createMeeting(
            MeetingDraft(title: "Selected", status: .ready, instructionsSnapshot: "Notes")
        )
        let otherID = try repository.createMeeting(
            MeetingDraft(title: "Other", status: .ready, instructionsSnapshot: "Notes")
        )

        try repository.deleteMeeting(id: selectedID)

        XCTAssertNil(try repository.meeting(id: selectedID))
        XCTAssertNotNil(try repository.meeting(id: otherID))
        XCTAssertEqual(try pendingCleanup(in: controller).map(\.meetingID), [selectedID])
        XCTAssertEqual(cleaner.deletedIDs, [selectedID])

        cleaner.shouldFail = false
        XCTAssertEqual(try repository.retryPendingFileCleanup(), [])
        XCTAssertTrue(try pendingCleanup(in: controller).isEmpty)
        XCTAssertEqual(cleaner.deletedIDs, [selectedID, selectedID])
    }

    func testRecordingPathTraversalAndWrongMeetingAreRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperContainment-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try AppPaths(rootURL: root)
        let first = UUID()
        let second = UUID()
        let wrongMeetingFile = try paths.recordingDirectory(for: second)
            .appendingPathComponent("microphone.m4a")

        XCTAssertThrowsError(try paths.recordingFileURL(relativePath: "../private.m4a"))
        XCTAssertThrowsError(
            try paths.relativeRecordingPath(for: wrongMeetingFile, meetingID: first)
        )
    }

    func testMeetingDirectorySymlinkCannotRedirectDeletionToAnotherMeeting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperSymlinkDeletion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try AppPaths(rootURL: root)
        let requestedID = UUID()
        let retainedID = UUID()
        let retainedDirectory = try paths.recordingDirectory(for: retainedID)
        let redirectedPath = paths.recordingsURL
            .appendingPathComponent("meeting-\(requestedID.uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: redirectedPath, withDestinationURL: retainedDirectory)

        XCTAssertThrowsError(try paths.deleteRecordingDirectory(for: requestedID)) {
            XCTAssertEqual($0 as? PersistenceError, .unsafePath)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDirectory.path))
    }

    private func pendingCleanup(in controller: PersistenceController) throws -> [RecordingCleanupEntity] {
        try controller.container.mainContext.fetch(FetchDescriptor<RecordingCleanupEntity>())
    }
}

private final class RecordingCleanerSpy: RecordingDirectoryCleaning {
    var shouldFail = false
    var deletedIDs: [UUID] = []

    func deleteRecordingDirectory(for meetingID: UUID) throws {
        deletedIDs.append(meetingID)
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
    }
}
