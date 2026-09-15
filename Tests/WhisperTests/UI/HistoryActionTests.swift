import Foundation
import XCTest
@testable import Whisper

@MainActor
final class HistoryActionTests: XCTestCase {
    func testMeetingPlainTextExportContainsUserContentButNoStorageMetadata() throws {
        let id = UUID()
        let meeting = MeetingSnapshot(
            id: id,
            title: "Planning",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060),
            duration: 60,
            status: .ready,
            progressCompleted: 2,
            progressTotal: 2,
            instructionsSnapshot: "private processing metadata",
            resultLanguage: "English",
            microphoneRelativePath: "meeting-\(id.uuidString)/microphone.m4a",
            systemAudioRelativePath: "meeting-\(id.uuidString)/system.m4a",
            microphoneStartOffset: 0,
            systemAudioStartOffset: 0,
            processedText: "Decision summary",
            errorMessage: "hidden failure metadata",
            failureKind: .processing,
            retryStage: .processing
        )
        let segments = [
            TranscriptSegment(meetingID: id, source: .you, startTime: 3, endTime: 4, text: "Hello"),
            TranscriptSegment(meetingID: id, source: .others, startTime: 5, endTime: 6, text: "Hi"),
        ]
        let entry = HistoryEntry(content: .recording(meeting, segments))

        let text = HistoryTextExporter.text(for: entry)

        XCTAssertTrue(text.contains("Planning"))
        XCTAssertTrue(text.contains("[00:03] You: Hello"))
        XCTAssertTrue(text.contains("Decision summary"))
        XCTAssertFalse(text.contains("microphone.m4a"))
        XCTAssertFalse(text.contains(id.uuidString))
        XCTAssertFalse(text.contains("private processing metadata"))
        XCTAssertFalse(text.contains("hidden failure metadata"))
    }

    func testPlainTextExporterWritesAtomicallyAndUsesSafeFilename() throws {
        let snapshot = DictationSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 2,
            modeID: nil,
            modeNameSnapshot: "Translate / unsafe:name",
            modeInstructionsSnapshot: "Hidden instruction",
            detectedLanguages: ["ru"],
            originalText: "Привет",
            outputText: "Hello",
            targetApplicationBundleID: "com.private.target",
            status: .ready,
            errorMessage: nil
        )
        let entry = HistoryEntry(content: .dictation(snapshot))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperExport-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: destination) }

        try HistoryTextExporter.export(entry, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), HistoryTextExporter.text(for: entry))
        XCTAssertEqual(HistoryTextExporter.suggestedFilename(for: entry), "Translate unsafe name.txt")
        XCTAssertFalse(HistoryTextExporter.text(for: entry).contains("com.private.target"))
        XCTAssertFalse(HistoryTextExporter.text(for: entry).contains("Hidden instruction"))
    }

    func testCopyResultContainsOnlyProcessedTextAndRequiresAResult() {
        let fixture = Fixture()
        let dictation = HistoryEntry(content: .dictation(fixture.dictation))
        let meeting = HistoryEntry(content: .recording(fixture.meeting, fixture.segments))

        XCTAssertEqual(HistoryTextExporter.resultText(for: dictation), "Processed dictation")
        XCTAssertEqual(HistoryTextExporter.resultText(for: meeting), "Processed meeting")
        XCTAssertFalse(try! XCTUnwrap(HistoryTextExporter.resultText(for: meeting)).contains("Private transcript"))

        let emptyMeeting = HistoryEntry(content: .recording(fixture.meetingWithEmptyResult, fixture.segments))
        XCTAssertNil(HistoryTextExporter.resultText(for: emptyMeeting))
        XCTAssertFalse(emptyMeeting.hasCopyableResult)
    }
}

private struct Fixture {
    let dictation = DictationSnapshot(
        id: UUID(), createdAt: Date(), duration: 1, modeID: nil,
        modeNameSnapshot: "Default", modeInstructionsSnapshot: "Instructions",
        detectedLanguages: [], originalText: "Private original", outputText: "Processed dictation",
        targetApplicationBundleID: nil, status: .ready, errorMessage: nil
    )
    let meeting: MeetingSnapshot
    let meetingWithEmptyResult: MeetingSnapshot
    let segments: [TranscriptSegment]

    init() {
        let id = UUID()
        meeting = Self.meeting(id: id, result: "Processed meeting")
        meetingWithEmptyResult = Self.meeting(id: id, result: "")
        segments = [TranscriptSegment(
            meetingID: id, source: .others, startTime: 0, endTime: 1, text: "Private transcript"
        )]
    }

    private static func meeting(id: UUID, result: String) -> MeetingSnapshot {
        MeetingSnapshot(
            id: id, title: "Call", startedAt: Date(), endedAt: Date(), duration: 1,
            status: .ready, progressCompleted: 1, progressTotal: 1,
            instructionsSnapshot: "Instructions", resultLanguage: nil,
            microphoneRelativePath: "", systemAudioRelativePath: "",
            microphoneStartOffset: 0, systemAudioStartOffset: 0,
            processedText: result, errorMessage: nil, failureKind: nil, retryStage: nil
        )
    }
}
