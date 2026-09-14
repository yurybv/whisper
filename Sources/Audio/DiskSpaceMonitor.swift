import Foundation

struct DiskSpaceMonitor: Sendable {
    static let minimumAvailableBytes: Int64 = 2_000_000_000
    static let warningAvailableBytes: Int64 = 4_000_000_000

    enum State: Sendable, Equatable {
        case blocked(availableBytes: Int64)
        case warning(availableBytes: Int64)
        case ready(availableBytes: Int64)
    }

    private let availableCapacity: @Sendable (URL) throws -> Int64

    init(
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = {
            try Self.readAvailableCapacity(at: $0)
        }
    ) {
        self.availableCapacity = availableCapacity
    }

    func state(for url: URL) throws -> State {
        let bytes = try availableCapacity(url)
        if bytes < Self.minimumAvailableBytes {
            return .blocked(availableBytes: bytes)
        }
        if bytes < Self.warningAvailableBytes {
            return .warning(availableBytes: bytes)
        }
        return .ready(availableBytes: bytes)
    }

    private static func readAvailableCapacity(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        if let bytes = values.volumeAvailableCapacityForImportantUsage {
            return bytes
        }
        if let bytes = values.volumeAvailableCapacity {
            return Int64(bytes)
        }
        throw DiskSpaceMonitorError.capacityUnavailable
    }
}

enum DiskSpaceMonitorError: Error, Sendable, Equatable {
    case capacityUnavailable
}
