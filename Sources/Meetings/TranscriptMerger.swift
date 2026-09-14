import Foundation

struct DiarizedChunkTranscript: Sendable, Equatable {
    let source: MeetingAudioSource
    let startOffset: TimeInterval
    let response: DiarizedTranscriptionResponse
}

enum TranscriptMergerError: Error, Sendable, Equatable {
    case invalidTimestamp
}

struct TranscriptMerger: Sendable {
    func merge(
        meetingID: UUID,
        chunks: [DiarizedChunkTranscript]
    ) throws -> [TranscriptSegment] {
        var ordinal = 0
        var candidates: [Candidate] = []

        for chunk in chunks {
            guard chunk.startOffset.isFinite, chunk.startOffset >= 0 else {
                throw TranscriptMergerError.invalidTimestamp
            }
            for apiSegment in chunk.response.segments {
                guard apiSegment.start.isFinite,
                      apiSegment.end.isFinite,
                      apiSegment.start >= 0,
                      apiSegment.end > apiSegment.start else {
                    throw TranscriptMergerError.invalidTimestamp
                }
                let text = normalize(apiSegment.text)
                guard !text.isEmpty else { continue }
                let startTime = chunk.startOffset + apiSegment.start
                let endTime = chunk.startOffset + apiSegment.end
                guard startTime.isFinite, endTime.isFinite else {
                    throw TranscriptMergerError.invalidTimestamp
                }
                candidates.append(
                    Candidate(
                        source: transcriptSource(for: chunk.source),
                        startTime: startTime,
                        endTime: endTime,
                        text: text,
                        ordinal: ordinal
                    )
                )
                ordinal += 1
            }
        }

        let ordered = candidates.sorted {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            if $0.endTime != $1.endTime { return $0.endTime < $1.endTime }
            if $0.source != $1.source { return $0.source == .you }
            return $0.ordinal < $1.ordinal
        }
        var unique: [Candidate] = []
        for candidate in ordered {
            guard !unique.contains(where: { isDuplicate(candidate, of: $0) }) else {
                continue
            }
            unique.append(candidate)
        }

        var merged: [TranscriptSegment] = []
        for candidate in unique {
            if let last = merged.last,
               last.source == candidate.source,
               candidate.startTime - last.endTime < 5 {
                merged[merged.count - 1] = TranscriptSegment(
                    id: last.id,
                    meetingID: meetingID,
                    source: last.source,
                    startTime: last.startTime,
                    endTime: max(last.endTime, candidate.endTime),
                    text: "\(last.text) \(candidate.text)"
                )
            } else {
                merged.append(
                    TranscriptSegment(
                        meetingID: meetingID,
                        source: candidate.source,
                        startTime: candidate.startTime,
                        endTime: candidate.endTime,
                        text: candidate.text
                    )
                )
            }
        }
        return merged
    }

    private func transcriptSource(for source: MeetingAudioSource) -> TranscriptSource {
        switch source {
        case .microphone: .you
        case .systemAudio: .others
        }
    }

    private func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func isDuplicate(_ lhs: Candidate, of rhs: Candidate) -> Bool {
        guard lhs.source == rhs.source, lhs.text == rhs.text else { return false }
        let overlap = max(0, min(lhs.endTime, rhs.endTime) - max(lhs.startTime, rhs.startTime))
        let shorterDuration = min(lhs.endTime - lhs.startTime, rhs.endTime - rhs.startTime)
        return overlap / shorterDuration >= 0.5
    }
}

private struct Candidate {
    let source: TranscriptSource
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let ordinal: Int
}
