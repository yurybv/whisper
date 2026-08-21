import SwiftData
import Foundation

@MainActor
final class PersistenceController {
    let container: ModelContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let schema = Schema([
            ModeEntity.self,
            DictationEntity.self,
            MeetingEntity.self,
            TranscriptSegmentEntity.self
        ])
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory
            )
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
    }
}
