import Foundation
import XCTest
@testable import Whisper

final class TranscriptMergerTests: XCTestCase {
    private let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    func testMapsSourcesAddsOffsetsSortsAndPreservesMixedLanguage() throws {
        let chunks = [
            DiarizedChunkTranscript(
                source: .systemAudio,
                startOffset: 20,
                response: response([
                    .init(speaker: "speaker_9", text: "  Да, ship it.  ", start: 1, end: 3)
                ])
            ),
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "speaker_0", text: "Hello\n   мир", start: 2, end: 4)
                ])
            )
        ]

        let merged = try TranscriptMerger().merge(meetingID: meetingID, chunks: chunks)

        XCTAssertEqual(merged.map(\.source), [.you, .others])
        XCTAssertEqual(merged.map(\.startTime), [2, 21])
        XCTAssertEqual(merged.map(\.endTime), [4, 23])
        XCTAssertEqual(merged.map(\.text), ["Hello мир", "Да, ship it."])
        XCTAssertTrue(merged.allSatisfy { $0.meetingID == meetingID })
    }

    func testRemovesMatchingOverlapDuplicateAtFiftyPercent() throws {
        let chunks = [
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "Next topic.", start: 1_199, end: 1_203)
                ])
            ),
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 1_199,
                response: response([
                    .init(speaker: "B", text: " Next   topic. ", start: 2, end: 6)
                ])
            )
        ]

        let merged = try TranscriptMerger().merge(meetingID: meetingID, chunks: chunks)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.text, "Next topic.")
        XCTAssertEqual(merged.first?.startTime, 1_199)
        XCTAssertEqual(merged.first?.endTime, 1_203)
    }

    func testKeepsMatchingOverlappingTextFromDifferentSources() throws {
        let chunks = [
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "Agreed", start: 0, end: 4)
                ])
            ),
            DiarizedChunkTranscript(
                source: .systemAudio,
                startOffset: 0,
                response: response([
                    .init(speaker: "B", text: "Agreed", start: 1, end: 4)
                ])
            )
        ]

        let merged = try TranscriptMerger().merge(meetingID: meetingID, chunks: chunks)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.source), [.you, .others])
    }

    func testDoesNotDeduplicateMatchingTextBelowFiftyPercentOverlap() throws {
        let chunks = [
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "Repeat", start: 0, end: 4)
                ])
            ),
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "Repeat", start: 3, end: 7)
                ])
            )
        ]

        let merged = try TranscriptMerger().merge(meetingID: meetingID, chunks: chunks)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .you)
        XCTAssertEqual(merged.first?.text, "Repeat Repeat")
    }

    func testCoalescesAdjacentSameSourceUnderFiveSecondsOnly() throws {
        let chunks = [
            DiarizedChunkTranscript(
                source: .microphone,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "First.", start: 0, end: 2),
                    .init(speaker: "B", text: "Second.", start: 6.9, end: 8),
                    .init(speaker: "A", text: "Third.", start: 13, end: 14)
                ])
            )
        ]

        let merged = try TranscriptMerger().merge(meetingID: meetingID, chunks: chunks)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].text, "First. Second.")
        XCTAssertEqual(merged[0].startTime, 0)
        XCTAssertEqual(merged[0].endTime, 8)
        XCTAssertEqual(merged[1].text, "Third.")
    }

    func testRejectsMalformedTimestampsWithoutMutatingPriorOutput() throws {
        let merger = TranscriptMerger()
        let valid = try merger.merge(
            meetingID: meetingID,
            chunks: [
                DiarizedChunkTranscript(
                    source: .microphone,
                    startOffset: 0,
                    response: response([
                        .init(speaker: "A", text: "Saved", start: 0, end: 1)
                    ])
                )
            ]
        )
        let malformed = [
            DiarizedChunkTranscript(
                source: .systemAudio,
                startOffset: 0,
                response: response([
                    .init(speaker: "A", text: "Broken", start: 2, end: 1)
                ])
            )
        ]

        XCTAssertThrowsError(try merger.merge(meetingID: meetingID, chunks: malformed)) {
            XCTAssertEqual($0 as? TranscriptMergerError, .invalidTimestamp)
        }
        XCTAssertEqual(valid.map(\.text), ["Saved"])
    }

    func testMalformedDiarizedJSONFailsDecoding() {
        let data = Data(#"{"text":"Broken","segments":[{"speaker":"A","text":"Missing end","start":0}]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(DiarizedTranscriptionResponse.self, from: data))
    }

    private func response(_ segments: [DiarizedSegment]) -> DiarizedTranscriptionResponse {
        DiarizedTranscriptionResponse(text: nil, segments: segments)
    }
}
