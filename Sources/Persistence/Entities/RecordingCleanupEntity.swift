import Foundation
import SwiftData

@Model
final class RecordingCleanupEntity {
    @Attribute(.unique) var meetingID: UUID
    var relativeDirectoryPath: String
    var createdAt: Date

    init(meetingID: UUID, createdAt: Date = Date()) {
        self.meetingID = meetingID
        relativeDirectoryPath = "meeting-\(meetingID.uuidString)"
        self.createdAt = createdAt
    }
}
