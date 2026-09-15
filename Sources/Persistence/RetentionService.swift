import Foundation

struct RetentionReport: Equatable, Sendable {
    let pendingFileCleanup: Int
}

@MainActor
final class RetentionService {
    private let repository: HistoryRepository

    init(repository: HistoryRepository) {
        self.repository = repository
    }

    func perform(policy: RetentionPolicy) throws -> RetentionReport {
        switch policy {
        case .forever:
            break
        }
        let pending = try repository.retryPendingFileCleanup()
        return RetentionReport(pendingFileCleanup: pending.count)
    }
}
