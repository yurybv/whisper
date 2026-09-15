import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import Whisper

@MainActor
final class HistorySearchModelTests: XCTestCase {
    func testSearchesBothKindsAndFiltersNewestFirst() {
        let fixture = Fixture()

        XCTAssertEqual(fixture.model.filteredEntries.map(\.id), [fixture.meeting.id, fixture.dictation.id])

        fixture.model.query = "decision"
        XCTAssertEqual(fixture.model.filteredEntries.map(\.id), [fixture.meeting.id])

        fixture.model.query = "translated"
        XCTAssertEqual(fixture.model.filteredEntries.map(\.id), [fixture.dictation.id])

        fixture.model.query = ""
        fixture.model.filter = .recordings
        XCTAssertEqual(fixture.model.filteredEntries.map(\.id), [fixture.meeting.id])
    }

    func testGroupsTodayAndYesterdayInStableOrder() {
        let fixture = Fixture()

        XCTAssertEqual(fixture.model.groups.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(fixture.model.groups.flatMap(\.entries).map(\.id), [fixture.meeting.id, fixture.dictation.id])
    }

    func testSelectedEntryPreservesDetailSnapshotsAndSegments() {
        let fixture = Fixture()
        fixture.model.select(fixture.meeting.id)

        guard case let .recording(meeting, segments) = fixture.model.selectedEntry?.content else {
            return XCTFail("Expected recording details")
        }
        XCTAssertEqual(meeting.instructionsSnapshot, "List decisions")
        XCTAssertEqual(segments.map(\.text), ["Decision made"])
    }

    func testFilterAndSearchNeverLeaveHiddenSelectionVisible() {
        let fixture = Fixture()
        fixture.model.select(fixture.meeting.id)

        fixture.model.filter = .dictations
        XCTAssertEqual(fixture.model.selectedEntry?.id, fixture.dictation.id)

        fixture.model.query = "no match"
        XCTAssertNil(fixture.model.selectedEntry)
    }

    func testRetryableRecordingShowsAttentionStateWithoutActiveProgress() {
        let fixture = Fixture()
        let meeting = retryableCopy(of: fixture.meeting)
        let entry = HistoryEntry(content: .recording(meeting, []))

        XCTAssertEqual(entry.status, "Needs Retry")
        XCTAssertFalse(meeting.showsActiveProcessingProgress)
    }

    func testAccessibleRowSummaryIncludesTimeAndPreview() {
        let entry = try! XCTUnwrap(Fixture().model.entries.first)

        XCTAssertTrue(entry.accessibilitySummary.contains(entry.preview))
        XCTAssertTrue(entry.accessibilitySummary.contains(entry.date.formatted(date: .omitted, time: .shortened)))
    }

    func testLoadFailureExposesErrorAndNoPrivateFallbackData() {
        let model = HistorySearchModel(repository: FailingHistoryReader(), now: Date.init)

        model.reload()

        XCTAssertEqual(model.entries, [])
        XCTAssertEqual(model.errorMessage, "History could not be loaded.")
    }

    func testPopulatedEmptyAndErrorViewsRenderDistinctOffscreenStates() throws {
        let populated = Fixture().model
        let empty = HistorySearchModel(
            repository: StaticHistoryReader(
                snapshot: HistorySnapshot(dictations: [], meetings: [], segmentsByMeetingID: [:])
            )
        )
        empty.reload()
        let failure = HistorySearchModel(repository: FailingHistoryReader())
        failure.reload()

        let populatedImage = try snapshot(of: HistoryView(model: populated))
        let emptyImage = try snapshot(of: HistoryView(model: empty))
        let errorImage = try snapshot(of: HistoryView(model: failure))

        XCTAssertGreaterThan(populatedImage.count, 20_000)
        XCTAssertGreaterThan(emptyImage.count, 20_000)
        XCTAssertGreaterThan(errorImage.count, 20_000)
        XCTAssertNotEqual(populatedImage, emptyImage)
        XCTAssertNotEqual(emptyImage, errorImage)
        for (name, data) in [("History populated", populatedImage), ("History empty", emptyImage), ("History error", errorImage)] {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func snapshot<Content: View>(of view: Content) throws -> Data {
        let size = NSSize(width: 1_040, height: 800)
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func retryableCopy(of value: MeetingSnapshot) -> MeetingSnapshot {
        MeetingSnapshot(
            id: value.id,
            title: value.title,
            startedAt: value.startedAt,
            endedAt: value.endedAt,
            duration: value.duration,
            status: .captured,
            progressCompleted: 1,
            progressTotal: 2,
            instructionsSnapshot: value.instructionsSnapshot,
            resultLanguage: value.resultLanguage,
            microphoneRelativePath: value.microphoneRelativePath,
            systemAudioRelativePath: value.systemAudioRelativePath,
            microphoneStartOffset: value.microphoneStartOffset,
            systemAudioStartOffset: value.systemAudioStartOffset,
            processedText: value.processedText,
            errorMessage: "Check your network connection, then retry.",
            failureKind: .network,
            retryStage: .processing
        )
    }
}

@MainActor
private struct Fixture {
    let now: Date
    let dictation: DictationSnapshot
    let meeting: MeetingSnapshot
    let model: HistorySearchModel

    init() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        self.now = now
        dictation = DictationSnapshot(
            id: UUID(),
            createdAt: now.addingTimeInterval(-86_400),
            duration: 3,
            modeID: nil,
            modeNameSnapshot: "Translate",
            modeInstructionsSnapshot: "Translate to English",
            detectedLanguages: ["ru"],
            originalText: "Исходный текст",
            outputText: "Translated result",
            targetApplicationBundleID: "com.apple.TextEdit",
            status: .ready,
            errorMessage: nil
        )
        meeting = MeetingSnapshot(
            id: UUID(),
            title: "Product call",
            startedAt: now.addingTimeInterval(-60),
            endedAt: now,
            duration: 60,
            status: .ready,
            progressCompleted: 2,
            progressTotal: 2,
            instructionsSnapshot: "List decisions",
            resultLanguage: "English",
            microphoneRelativePath: "microphone.m4a",
            systemAudioRelativePath: "system.m4a",
            microphoneStartOffset: 0,
            systemAudioStartOffset: 0,
            processedText: "Decision summary",
            errorMessage: nil,
            failureKind: nil,
            retryStage: nil
        )
        let segment = TranscriptSegment(
            meetingID: meeting.id,
            source: .others,
            startTime: 3,
            endTime: 5,
            text: "Decision made"
        )
        model = HistorySearchModel(
            repository: StaticHistoryReader(
                snapshot: HistorySnapshot(
                    dictations: [dictation],
                    meetings: [meeting],
                    segmentsByMeetingID: [meeting.id: [segment]]
                )
            ),
            now: { now }
        )
        model.reload()
    }
}

@MainActor
private struct StaticHistoryReader: HistoryReading {
    let snapshot: HistorySnapshot
    func historySnapshot() throws -> HistorySnapshot { snapshot }
}

@MainActor
private struct FailingHistoryReader: HistoryReading {
    func historySnapshot() throws -> HistorySnapshot { throw PersistenceError.meetingNotFound }
}
