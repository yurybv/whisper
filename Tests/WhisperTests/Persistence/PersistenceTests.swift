import XCTest
import SwiftData
@testable import Whisper

final class PersistenceTests: XCTestCase {
    @MainActor
    func testSeedsExactlyThreeCanonicalBuiltInModesIdempotently() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = ModeRepository(context: controller.container.mainContext)

        try repository.seedBuiltInModes()
        try repository.seedBuiltInModes()

        let modes = try repository.fetchAll()
        XCTAssertEqual(modes, ModeDefinition.builtInModes)
        XCTAssertEqual(modes.filter(\.isDefault).count, 1)
        XCTAssertEqual(modes.first(where: \.isDefault), ModeDefinition.defaultMode)
    }

    @MainActor
    func testSeedRepairsCanonicalRowsAndPreservesUnrelatedCustomMode() throws {
        let controller = try PersistenceController(inMemory: true)
        let suiteName = "PersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = ModeRepository(
            context: controller.container.mainContext,
            userDefaults: defaults
        )
        let context = controller.container.mainContext
        let stale = ModeDefinition(
            id: ModeDefinition.russianEnglishWorkTechnicalMode.id,
            name: "Old preset name",
            instructions: "Old instructions",
            languageHint: "en",
            isDefault: true,
            isEnabled: false,
            sortIndex: 99,
            createdAt: Date(timeIntervalSince1970: 99),
            updatedAt: Date(timeIntervalSince1970: 99)
        )
        context.insert(ModeEntity(stale, normalizedName: "old preset name"))
        let custom = try repository.create(
            ModeDraft(
                name: "My Custom Mode",
                instructions: "Keep this content.",
                languageHint: "fr",
                isEnabled: false,
                sortIndex: 42
            )
        )
        try repository.seedBuiltInModes()

        let modes = try repository.fetchAll()
        XCTAssertEqual(
            modes.filter(\.isBuiltIn),
            ModeDefinition.builtInModes
        )
        XCTAssertEqual(modes.first(where: { $0.id == custom.id }), custom)
        XCTAssertEqual(modes.filter(\.isDefault), [.defaultMode])
    }

    @MainActor
    func testSeedPreservesActiveCustomMode() throws {
        let controller = try PersistenceController(inMemory: true)
        let suiteName = "PersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = ModeRepository(
            context: controller.container.mainContext,
            userDefaults: defaults
        )
        let custom = try repository.create(
            ModeDraft(
                name: "Active Custom",
                instructions: "Keep active.",
                languageHint: nil
            )
        )
        try repository.activate(custom.id)

        try repository.seedBuiltInModes()

        XCTAssertEqual(try repository.activeMode().id, custom.id)
    }

    @MainActor
    func testSeedRenamesBuiltInNameCollisionsDeterministically() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = ModeRepository(context: controller.container.mainContext)
        let first = try repository.create(
            ModeDraft(
                name: ModeDefinition.russianEnglishWorkTechnicalMode.name,
                instructions: "Preserve this first custom mode.",
                languageHint: "de"
            )
        )
        _ = try repository.create(
            ModeDraft(
                name: "\(ModeDefinition.russianEnglishWorkTechnicalMode.name) (Custom)",
                instructions: "Reserve the first suffix.",
                languageHint: nil
            )
        )

        try repository.seedBuiltInModes()

        let modes = try repository.fetchAll()
        let renamed = try XCTUnwrap(modes.first(where: { $0.id == first.id }))
        XCTAssertEqual(
            renamed.name,
            "\(ModeDefinition.russianEnglishWorkTechnicalMode.name) (Custom 2)"
        )
        XCTAssertEqual(renamed.instructions, "Preserve this first custom mode.")
        XCTAssertEqual(renamed.languageHint, "de")
        XCTAssertEqual(
            modes.first(where: { $0.id == ModeDefinition.russianEnglishWorkTechnicalMode.id }),
            ModeDefinition.russianEnglishWorkTechnicalMode
        )
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
        try repository.seedBuiltInModes()
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
            paths.metadataDirectoryURL,
            root.appendingPathComponent("Metadata", isDirectory: true)
        )
        XCTAssertEqual(
            paths.metadataStoreURL,
            root.appendingPathComponent("Metadata", isDirectory: true)
                .appendingPathComponent("Whisper.store")
        )
        XCTAssertEqual(
            meetingDirectory,
            paths.recordingsURL.appendingPathComponent("meeting-\(meetingID.uuidString)", isDirectory: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetingDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.temporaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.metadataDirectoryURL.path))

        for directory in [
            paths.rootURL,
            paths.recordingsURL,
            paths.temporaryURL,
            paths.metadataDirectoryURL,
            meetingDirectory
        ] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, 0o700)
        }
    }

    func testRejectsSymlinkedApplicationSupportRoot() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperRootSymlink-\(UUID().uuidString)", isDirectory: true)
        let destination = sandbox.appendingPathComponent("outside", isDirectory: true)
        let root = sandbox.appendingPathComponent("Whisper", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: destination)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        XCTAssertThrowsError(try AppPaths(rootURL: root)) {
            XCTAssertEqual($0 as? PersistenceError, .unsafePath)
        }
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
    func testMeetingRecoveryMetadataSurvivesReopeningStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperRecoveryStore-\(UUID().uuidString)", isDirectory: true)
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
                    title: "Recoverable",
                    status: .captured,
                    instructionsSnapshot: "Stable instruction",
                    resultLanguage: "Russian",
                    microphoneRelativePath: "meeting-\(meetingID.uuidString)/microphone.m4a",
                    systemAudioRelativePath: "meeting-\(meetingID.uuidString)/system.m4a",
                    microphoneStartOffset: 0.25,
                    systemAudioStartOffset: 0.75,
                    errorMessage: "Retry when online",
                    failureKind: .network,
                    retryStage: .processing
                )
            )
        }

        let controller = try PersistenceController(storeURL: storeURL)
        let meeting = try XCTUnwrap(
            HistoryRepository(context: controller.container.mainContext).meeting(id: meetingID)
        )
        XCTAssertEqual(meeting.instructionsSnapshot, "Stable instruction")
        XCTAssertEqual(meeting.resultLanguage, "Russian")
        XCTAssertEqual(meeting.microphoneStartOffset, 0.25)
        XCTAssertEqual(meeting.systemAudioStartOffset, 0.75)
        XCTAssertEqual(meeting.failureKind, .network)
        XCTAssertEqual(meeting.retryStage, .processing)
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
    func testRecentHistoryCombinesKindsNewestFirstAndHonorsLimit() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        var expectedIDs: [UUID] = []

        for offset in 0..<4 {
            let id = try repository.createDictation(
                DictationDraft(
                    createdAt: Date(timeIntervalSinceReferenceDate: TimeInterval(10 + offset)),
                    modeNameSnapshot: "Default",
                    modeInstructionsSnapshot: ModeDefinition.defaultInstructions,
                    originalText: "Original \(offset)",
                    outputText: "Output \(offset)",
                    status: .ready
                )
            )
            expectedIDs.append(id)
        }
        for offset in 0..<3 {
            let id = try repository.createMeeting(
                MeetingDraft(
                    title: "Meeting \(offset)",
                    startedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(20 + offset)),
                    status: .ready,
                    instructionsSnapshot: "Summarize."
                )
            )
            expectedIDs.append(id)
        }

        let recent = try repository.recentHistory(limit: 5)

        XCTAssertEqual(recent.map(\.id), Array(expectedIDs.reversed().prefix(5)))
        XCTAssertEqual(recent.first?.kind, .recording)
        XCTAssertEqual(recent.first?.title, "Meeting 2")
        XCTAssertEqual(recent.last?.kind, .dictation)
    }

    @MainActor
    func testHistorySnapshotReturnsFullRecordsAndChronologicalSegments() throws {
        let controller = try PersistenceController(inMemory: true)
        let repository = HistoryRepository(context: controller.container.mainContext)
        let dictationID = try repository.createDictation(
            DictationDraft(
                modeNameSnapshot: "Translate",
                modeInstructionsSnapshot: "Translate to English",
                originalText: "Привет",
                outputText: "Hello",
                status: .ready
            )
        )
        let meetingID = try repository.createMeeting(
            MeetingDraft(
                title: "Planning",
                status: .ready,
                instructionsSnapshot: "List decisions",
                processedText: "Decision summary"
            )
        )
        try repository.replaceSegments(
            meetingID: meetingID,
            segments: [
                TranscriptSegment(meetingID: meetingID, source: .others, startTime: 8, endTime: 9, text: "Second"),
                TranscriptSegment(meetingID: meetingID, source: .you, startTime: 2, endTime: 3, text: "First"),
            ]
        )

        let snapshot = try repository.historySnapshot()

        XCTAssertEqual(snapshot.dictations.map(\.id), [dictationID])
        XCTAssertEqual(snapshot.meetings.map(\.id), [meetingID])
        XCTAssertEqual(snapshot.segmentsByMeetingID[meetingID]?.map(\.text), ["First", "Second"])
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

    @MainActor
    func testRelocatorCopiesCompatibleLegacyStoreAndPreservesEveryEntity() throws {
        let fixture = StoreFixture()
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try seedStore(at: sandbox.legacyStoreURL, fixture: fixture)

        let canonicalURL = try PersistentStoreRelocator().prepareCanonicalStore(
            paths: sandbox.paths,
            legacyStoreURL: sandbox.legacyStoreURL
        )

        XCTAssertEqual(canonicalURL, sandbox.paths.metadataStoreURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.legacyStoreURL.path))
        let controller = try PersistenceController(storeURL: canonicalURL)
        let context = controller.container.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<ModeEntity>()).map(\.id), [fixture.modeID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<DictationEntity>()).map(\.id), [fixture.dictationID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeetingEntity>()).map(\.id), [fixture.meetingID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptSegmentEntity>()).map(\.id), [fixture.segmentID])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<RecordingCleanupEntity>()).map(\.meetingID),
            [fixture.cleanupMeetingID]
        )
    }

    @MainActor
    func testRelocatorUsesExistingCanonicalStoreWithoutTouchingLegacy() throws {
        let canonicalFixture = StoreFixture()
        let legacyFixture = StoreFixture()
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try seedStore(at: sandbox.paths.metadataStoreURL, fixture: canonicalFixture)
        try seedStore(at: sandbox.legacyStoreURL, fixture: legacyFixture)

        let canonicalURL = try PersistentStoreRelocator().prepareCanonicalStore(
            paths: sandbox.paths,
            legacyStoreURL: sandbox.legacyStoreURL
        )

        let controller = try PersistenceController(storeURL: canonicalURL)
        XCTAssertEqual(
            try controller.container.mainContext.fetch(FetchDescriptor<ModeEntity>()).map(\.id),
            [canonicalFixture.modeID]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.legacyStoreURL.path))
    }

    @MainActor
    func testRelocatorIsIdempotentAfterSuccessfulPromotion() throws {
        let fixture = StoreFixture()
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try seedStore(at: sandbox.legacyStoreURL, fixture: fixture)
        let relocator = PersistentStoreRelocator()

        let firstURL = try relocator.prepareCanonicalStore(
            paths: sandbox.paths,
            legacyStoreURL: sandbox.legacyStoreURL
        )
        let secondURL = try relocator.prepareCanonicalStore(
            paths: sandbox.paths,
            legacyStoreURL: sandbox.legacyStoreURL
        )

        XCTAssertEqual(firstURL, secondURL)
        let controller = try PersistenceController(storeURL: secondURL)
        XCTAssertEqual(
            try controller.container.mainContext.fetch(FetchDescriptor<ModeEntity>()).map(\.id),
            [fixture.modeID]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.legacyStoreURL.path))
    }

    @MainActor
    func testRelocatorIgnoresUnrelatedLegacyStore() throws {
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try Data("unrelated local database".utf8).write(to: sandbox.legacyStoreURL)

        let canonicalURL = try PersistentStoreRelocator().prepareCanonicalStore(
            paths: sandbox.paths,
            legacyStoreURL: sandbox.legacyStoreURL
        )

        XCTAssertEqual(canonicalURL, sandbox.paths.metadataStoreURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.legacyStoreURL.path))
    }

    @MainActor
    func testRelocatorLeavesLegacyUntouchedAndNoCanonicalStoreWhenCopyFails() throws {
        let fixture = StoreFixture()
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try seedStore(at: sandbox.legacyStoreURL, fixture: fixture)
        let relocator = PersistentStoreRelocator(copyItem: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        XCTAssertThrowsError(
            try relocator.prepareCanonicalStore(
                paths: sandbox.paths,
                legacyStoreURL: sandbox.legacyStoreURL
            )
        ) {
            XCTAssertEqual($0 as? PersistenceError, .metadataMigrationFailed)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.legacyStoreURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.paths.metadataStoreURL.path))
    }

    @MainActor
    func testExplicitMetadataStoreSurvivesReopen() throws {
        let fixture = StoreFixture()
        let sandbox = try makeStoreSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.applicationSupport) }
        try seedStore(at: sandbox.paths.metadataStoreURL, fixture: fixture)

        let controller = try PersistenceController(storeURL: sandbox.paths.metadataStoreURL)

        XCTAssertEqual(
            try controller.container.mainContext.fetch(FetchDescriptor<DictationEntity>()).map(\.id),
            [fixture.dictationID]
        )
    }

    @MainActor
    private func seedStore(at storeURL: URL, fixture: StoreFixture) throws {
        let controller = try PersistenceController(storeURL: storeURL)
        let context = controller.container.mainContext
        context.insert(
            ModeEntity(
                ModeDefinition(
                    id: fixture.modeID,
                    name: "Synthetic Mode",
                    instructions: "Synthetic instructions.",
                    languageHint: "en",
                    isDefault: false,
                    isEnabled: true
                ),
                normalizedName: "synthetic mode"
            )
        )
        let history = HistoryRepository(context: context)
        _ = try history.createDictation(
            DictationDraft(
                id: fixture.dictationID,
                modeID: fixture.modeID,
                modeNameSnapshot: "Synthetic Mode",
                modeInstructionsSnapshot: "Synthetic instructions.",
                originalText: "Synthetic input",
                outputText: "Synthetic output",
                status: .ready
            )
        )
        _ = try history.createMeeting(
            MeetingDraft(
                id: fixture.meetingID,
                title: "Synthetic meeting",
                status: .ready,
                instructionsSnapshot: "Synthetic meeting instructions."
            )
        )
        try history.replaceSegments(
            meetingID: fixture.meetingID,
            segments: [
                TranscriptSegment(
                    id: fixture.segmentID,
                    meetingID: fixture.meetingID,
                    source: .you,
                    startTime: 0,
                    endTime: 1,
                    text: "Synthetic segment"
                )
            ]
        )
        context.insert(RecordingCleanupEntity(meetingID: fixture.cleanupMeetingID))
        try context.save()
    }

    private func makeStoreSandbox() throws -> StoreSandbox {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperStoreMigration-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(
            rootURL: applicationSupport.appendingPathComponent("Whisper", isDirectory: true)
        )
        return StoreSandbox(
            applicationSupport: applicationSupport,
            paths: paths,
            legacyStoreURL: applicationSupport.appendingPathComponent("default.store")
        )
    }
}

private struct StoreFixture {
    let modeID = UUID()
    let dictationID = UUID()
    let meetingID = UUID()
    let segmentID = UUID()
    let cleanupMeetingID = UUID()
}

private struct StoreSandbox {
    let applicationSupport: URL
    let paths: AppPaths
    let legacyStoreURL: URL
}
