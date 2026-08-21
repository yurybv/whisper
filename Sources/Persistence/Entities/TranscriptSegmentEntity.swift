import Foundation
import SwiftData

enum TranscriptSource: String, Sendable, Codable, Equatable {
    case you
    case others
}

struct TranscriptSegment: Sendable, Equatable, Identifiable {
    let id: UUID
    let meetingID: UUID
    let source: TranscriptSource
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        source: TranscriptSource,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.meetingID = meetingID
        self.source = source
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

@Model
final class TranscriptSegmentEntity {
    @Attribute(.unique) var id: UUID
    var meetingID: UUID
    var sourceRaw: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var meeting: MeetingEntity

    init(_ segment: TranscriptSegment, meeting: MeetingEntity) {
        id = segment.id
        meetingID = segment.meetingID
        sourceRaw = segment.source.rawValue
        startTime = segment.startTime
        endTime = segment.endTime
        text = segment.text
        self.meeting = meeting
    }

    var source: TranscriptSource {
        TranscriptSource(rawValue: sourceRaw) ?? .others
    }

    var segment: TranscriptSegment {
        TranscriptSegment(
            id: id,
            meetingID: meetingID,
            source: source,
            startTime: startTime,
            endTime: endTime,
            text: text
        )
    }
}
