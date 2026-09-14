import Foundation
import XCTest
@testable import Whisper

final class MeetingTranscriberTests: XCTestCase {
    func testSkipsPersistedChunkLimitsConcurrencyAndReportsDurableProgress() async throws {
        let fixture = try TranscriberFixture(chunkCount: 3)
        defer { fixture.removeFiles() }
        let first = fixture.chunks[0]
        try fixture.resultStore.save(
            PersistedDiarizedChunk(
                key: first.key,
                source: first.source,
                startOffset: first.timelineStartOffset,
                response: response(text: "Already done", start: 0, end: 1)
            ),
            meetingID: fixture.meeting.id
        )
        let progress = ProgressRecorder()

        let segments = try await fixture.transcriber.transcribe(meeting: fixture.meeting) {
            await progress.append(completed: $0, total: $1)
        }

        let callCount = await fixture.client.callCount
        let maximumConcurrentCalls = await fixture.client.maximumConcurrentCalls
        let transcribedKeys = await fixture.preparer.transcribedKeys
        let progressValues = await progress.values
        XCTAssertEqual(callCount, 2)
        XCTAssertLessThanOrEqual(maximumConcurrentCalls, 2)
        XCTAssertEqual(transcribedKeys, Set(fixture.chunks.map(\.key)))
        XCTAssertEqual(try fixture.resultStore.load(meetingID: fixture.meeting.id).count, 3)
        XCTAssertEqual(progressValues, [ProgressValue(completed: 1, total: 3),
                                        ProgressValue(completed: 2, total: 3),
                                        ProgressValue(completed: 3, total: 3)])
        XCTAssertEqual(segments.map(\.text), ["Already done", "Chunk 1", "Chunk 2"])
    }

    func testPersistsSuccessfulSiblingBeforeFailureAndRetriesOnlyMissingChunk() async throws {
        let fixture = try TranscriberFixture(chunkCount: 2, failuresByName: ["chunk-1.m4a": 1])
        defer { fixture.removeFiles() }

        do {
            _ = try await fixture.transcriber.transcribe(meeting: fixture.meeting) { _, _ in }
            XCTFail("Expected the failed sibling to stop the batch")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        let persistedAfterFailure = try fixture.resultStore.load(meetingID: fixture.meeting.id)
        XCTAssertEqual(persistedAfterFailure.map(\.key), [fixture.chunks[0].key])
        let transcribedAfterFailure = await fixture.preparer.transcribedKeys
        let failedAfterFailure = await fixture.preparer.failedKeys
        XCTAssertEqual(transcribedAfterFailure, Set([fixture.chunks[0].key]))
        XCTAssertEqual(failedAfterFailure, Set([fixture.chunks[1].key]))

        let segments = try await fixture.transcriber.transcribe(meeting: fixture.meeting) { _, _ in }

        let callCount = await fixture.client.callCount
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(segments.map(\.text), ["Chunk 0", "Chunk 1"])
        XCTAssertEqual(try fixture.resultStore.load(meetingID: fixture.meeting.id).count, 2)
    }

    private func response(text: String, start: TimeInterval, end: TimeInterval) -> DiarizedTranscriptionResponse {
        DiarizedTranscriptionResponse(
            text: text,
            segments: [.init(speaker: "ignored", text: text, start: start, end: end)]
        )
    }
}

private struct ProgressValue: Equatable {
    let completed: Int
    let total: Int
}

private actor ProgressRecorder {
    private(set) var values: [ProgressValue] = []
    func append(completed: Int, total: Int) {
        values.append(ProgressValue(completed: completed, total: total))
    }
}

private struct TranscriberFixture {
    let root: URL
    let meeting: MeetingSnapshot
    let chunks: [PreparedMeetingChunk]
    let preparer: FakeMeetingChunkPreparer
    let client: FakeDiarizedClient
    let resultStore: DiarizedChunkResultStore
    let transcriber: MeetingTranscriber

    init(chunkCount: Int, failuresByName: [String: Int] = [:]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperMeetingTranscriberTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(rootURL: root)
        let meetingID = UUID()
        let directory = try paths.recordingDirectory(for: meetingID)
        var prepared: [PreparedMeetingChunk] = []
        for index in 0..<chunkCount {
            let url = directory.appendingPathComponent("chunk-\(index).m4a")
            try Data([UInt8(index)]).write(to: url)
            prepared.append(
                PreparedMeetingChunk(
                    key: "microphone-\(index)",
                    source: .microphone,
                    index: index,
                    timelineStartOffset: TimeInterval(index * 10),
                    fileURL: url
                )
            )
        }
        chunks = prepared
        meeting = MeetingSnapshot(
            id: meetingID,
            title: "Call",
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            endedAt: Date(timeIntervalSinceReferenceDate: 30),
            duration: 30,
            status: .captured,
            progressCompleted: 0,
            progressTotal: 0,
            instructionsSnapshot: "Summarize",
            resultLanguage: nil,
            microphoneRelativePath: "meeting-\(meetingID.uuidString)/microphone.m4a",
            systemAudioRelativePath: "meeting-\(meetingID.uuidString)/system.m4a",
            microphoneStartOffset: 0,
            systemAudioStartOffset: 0,
            processedText: "",
            errorMessage: nil,
            failureKind: nil,
            retryStage: nil
        )
        preparer = FakeMeetingChunkPreparer(chunks: prepared)
        client = FakeDiarizedClient(failuresByName: failuresByName)
        resultStore = DiarizedChunkResultStore(paths: paths)
        transcriber = MeetingTranscriber(
            client: client,
            chunkPreparer: preparer,
            resultStore: resultStore
        )
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private actor FakeMeetingChunkPreparer: MeetingChunkPreparing {
    private let chunks: [PreparedMeetingChunk]
    private(set) var transcribedKeys: Set<String> = []
    private(set) var failedKeys: Set<String> = []

    init(chunks: [PreparedMeetingChunk]) { self.chunks = chunks }
    func prepare(meeting: MeetingSnapshot) async throws -> [PreparedMeetingChunk] { chunks }
    func markTranscribed(_ chunk: PreparedMeetingChunk) async throws { transcribedKeys.insert(chunk.key) }
    func markFailed(_ chunk: PreparedMeetingChunk) async throws { failedKeys.insert(chunk.key) }
}

private actor FakeDiarizedClient: MeetingDiarizedTranscribing {
    private var failuresByName: [String: Int]
    private var activeCalls = 0
    private(set) var callCount = 0
    private(set) var maximumConcurrentCalls = 0

    init(failuresByName: [String: Int]) { self.failuresByName = failuresByName }

    func transcribeDiarized(fileURL: URL) async throws -> DiarizedTranscriptionResponse {
        callCount += 1
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        defer { activeCalls -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        let name = fileURL.lastPathComponent
        if let remaining = failuresByName[name], remaining > 0 {
            failuresByName[name] = remaining - 1
            throw URLError(.notConnectedToInternet)
        }
        let index = Int(name.replacingOccurrences(of: "chunk-", with: "")
            .replacingOccurrences(of: ".m4a", with: "")) ?? 0
        let text = "Chunk \(index)"
        return DiarizedTranscriptionResponse(
            text: text,
            segments: [.init(speaker: "ignored", text: text, start: 0, end: 1)]
        )
    }
}
