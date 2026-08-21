import XCTest
import SwiftData
@testable import Whisper

final class PersistenceTests: XCTestCase {
    @MainActor
    func testSeedsExactlyOneDefaultMode() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = ModeRepository(context: controller.container.mainContext)

        try repository.seedDefaultMode()
        try repository.seedDefaultMode()

        let modes = try repository.fetchAll()
        XCTAssertEqual(modes.filter(\.isDefault).count, 1)
        XCTAssertEqual(modes.first(where: \.isDefault), ModeDefinition.defaultMode)
    }

    @MainActor
    func testSeedRepairsAnExistingCustomModeNamedDefault() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = ModeRepository(context: controller.container.mainContext)
        _ = try repository.create(
            ModeDraft(
                name: "Default",
                instructions: "Temporary instructions.",
                languageHint: nil
            )
        )

        try repository.seedDefaultMode()

        XCTAssertEqual(try repository.fetchAll(), [ModeDefinition.defaultMode])
    }

    @MainActor
    func testDeletingActiveCustomModeFallsBackToDefault() throws {
        let controller = try PersistenceController(inMemory: true)
        let suiteName = "PersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = ModeRepository(
            context: controller.container.mainContext,
            userDefaults: defaults
        )
        try repository.seedDefaultMode()
        let custom = try repository.create(
            ModeDraft(
                name: "English",
                instructions: "Translate to English.",
                languageHint: "ru"
            )
        )

        try repository.activate(custom.id)
        try repository.delete(custom.id)

        XCTAssertEqual(try repository.activeMode(), ModeDefinition.defaultMode)
    }

    func testCreatesApplicationSupportLayoutUnderInjectedRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperPaths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppPaths(rootURL: root)
        let meetingID = UUID()
        let meetingDirectory = try paths.recordingDirectory(for: meetingID)

        XCTAssertEqual(paths.rootURL, root.standardizedFileURL)
        XCTAssertEqual(paths.recordingsURL, root.appendingPathComponent("Recordings", isDirectory: true))
        XCTAssertEqual(paths.temporaryURL, root.appendingPathComponent("Temporary", isDirectory: true))
        XCTAssertEqual(
            meetingDirectory,
            paths.recordingsURL.appendingPathComponent("meeting-\(meetingID.uuidString)", isDirectory: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetingDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.temporaryURL.path))
    }

    func testRejectsDeletionOutsideRecordingsRoot() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperPathSafety-\(UUID().uuidString)", isDirectory: true)
        let root = sandbox.appendingPathComponent("Whisper", isDirectory: true)
        let outside = sandbox.appendingPathComponent("meeting-outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let paths = try AppPaths(rootURL: root)

        XCTAssertThrowsError(try paths.deleteRecordingDirectory(at: outside)) {
            XCTAssertEqual($0 as? PersistenceError, .unsafePath)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testDeletesOnlyRequestedMeetingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperDeletion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try AppPaths(rootURL: root)
        let deletedID = UUID()
        let retainedID = UUID()
        let deletedDirectory = try paths.recordingDirectory(for: deletedID)
        let retainedDirectory = try paths.recordingDirectory(for: retainedID)

        try paths.deleteRecordingDirectory(for: deletedID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.recordingsURL.path))
    }

    @MainActor
    func testIncompleteMeetingsReturnsOnlyRecoverableStates() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        let capturedID = UUID()
        let readyID = UUID()
        _ = try repository.createMeeting(
            MeetingDraft(
                id: capturedID,
                title: "Captured call",
                startedAt: Date(timeIntervalSinceReferenceDate: 10),
                status: .captured,
                instructionsSnapshot: "Summarize.",
                microphoneRelativePath: "meeting-\(capturedID.uuidString)/microphone.m4a",
                systemAudioRelativePath: "meeting-\(capturedID.uuidString)/system.m4a"
            )
        )
        _ = try repository.createMeeting(
            MeetingDraft(
                id: readyID,
                title: "Ready call",
                startedAt: Date(timeIntervalSinceReferenceDate: 20),
                status: .ready,
                instructionsSnapshot: "Summarize.",
                microphoneRelativePath: "meeting-\(readyID.uuidString)/microphone.m4a",
                systemAudioRelativePath: "meeting-\(readyID.uuidString)/system.m4a"
            )
        )

        let meetings = try repository.incompleteMeetings()

        XCTAssertEqual(meetings.map(\.id), [capturedID])
        XCTAssertEqual(meetings.first?.status, .captured)
    }

    @MainActor
    func testIncompleteMeetingsRemainQueryableAfterReopeningStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("Whisper.store")
        let meetingID = UUID()

        do {
            let controller = try PersistenceController(storeURL: storeURL)
            let repository = HistoryRepository(context: controller.container.mainContext)
            _ = try repository.createMeeting(
                MeetingDraft(
                    id: meetingID,
                    title: "Interrupted call",
                    status: .transcribing,
                    instructionsSnapshot: "Summarize."
                )
            )
        }

        let reopenedController = try PersistenceController(storeURL: storeURL)
        let reopenedRepository = HistoryRepository(context: reopenedController.container.mainContext)

        XCTAssertEqual(try reopenedRepository.incompleteMeetings().map(\.id), [meetingID])
    }

    @MainActor
    func testStoresAndUpdatesDictationMetadata() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        let modeID = UUID()
        let id = try repository.createDictation(
            DictationDraft(
                createdAt: Date(timeIntervalSinceReferenceDate: 30),
                duration: 1.25,
                modeID: modeID,
                modeNameSnapshot: "Default",
                modeInstructionsSnapshot: ModeDefinition.defaultInstructions,
                detectedLanguages: ["ru"],
                originalText: "Привет",
                outputText: "Привет.",
                targetApplicationBundleID: "com.apple.TextEdit",
                status: .processing
            )
        )

        try repository.updateDictation(
            id: id,
            mutation: .status(.ready, errorMessage: nil)
        )

        let snapshot = try XCTUnwrap(repository.dictation(id: id))
        XCTAssertEqual(snapshot.modeID, modeID)
        XCTAssertEqual(snapshot.detectedLanguages, ["ru"])
        XCTAssertEqual(snapshot.outputText, "Привет.")
        XCTAssertEqual(snapshot.status, .ready)
    }

    @MainActor
    func testReplacesSegmentsAndCascadesWhenMeetingIsDeleted() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        let meetingID = try repository.createMeeting(
            MeetingDraft(title: "Project call", instructionsSnapshot: "Summarize.")
        )
        let segments = [
            TranscriptSegment(
                meetingID: meetingID,
                source: .you,
                startTime: 0,
                endTime: 1,
                text: "Hello"
            ),
            TranscriptSegment(
                meetingID: meetingID,
                source: .others,
                startTime: 1,
                endTime: 2,
                text: "Hi"
            )
        ]

        try repository.replaceSegments(meetingID: meetingID, segments: segments)

        let stored = try controller.container.mainContext.fetch(
            FetchDescriptor<TranscriptSegmentEntity>(sortBy: [SortDescriptor(\.startTime)])
        )
        XCTAssertEqual(stored.map(\.source), [.you, .others])
        XCTAssertEqual(stored.map(\.text), ["Hello", "Hi"])

        try repository.deleteMeeting(id: meetingID)

        XCTAssertTrue(try controller.container.mainContext.fetch(FetchDescriptor<MeetingEntity>()).isEmpty)
        XCTAssertTrue(try controller.container.mainContext.fetch(FetchDescriptor<TranscriptSegmentEntity>()).isEmpty)
    }

    @MainActor
    func testReplacingSegmentsMaintainsOneRelationshipPerSegment() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        let meetingID = try repository.createMeeting(
            MeetingDraft(title: "Project call", instructionsSnapshot: "Summarize.")
        )

        try repository.replaceSegments(
            meetingID: meetingID,
            segments: [
                TranscriptSegment(
                    meetingID: meetingID,
                    source: .you,
                    startTime: 0,
                    endTime: 1,
                    text: "Hello"
                )
            ]
        )
        try repository.replaceSegments(
            meetingID: meetingID,
            segments: [
                TranscriptSegment(
                    meetingID: meetingID,
                    source: .others,
                    startTime: 1,
                    endTime: 2,
                    text: "Replacement"
                )
            ]
        )

        let meeting = try XCTUnwrap(
            controller.container.mainContext.fetch(FetchDescriptor<MeetingEntity>()).first
        )
        XCTAssertEqual(meeting.segments.count, 1)
        XCTAssertEqual(meeting.segments.first?.text, "Replacement")
        XCTAssertEqual(meeting.segments.first?.meeting.id, meetingID)
    }
}
