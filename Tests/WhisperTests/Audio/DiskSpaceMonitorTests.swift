import Foundation
import XCTest
@testable import Whisper

final class DiskSpaceMonitorTests: XCTestCase {
    func testBlocksRecordingBelowTwoGigabytes() throws {
        let monitor = DiskSpaceMonitor { _ in 1_999_999_999 }

        XCTAssertEqual(
            try monitor.state(for: URL(fileURLWithPath: "/tmp")),
            .blocked(availableBytes: 1_999_999_999)
        )
    }

    func testAllowsRecordingAtTwoGigabytesWithWarning() throws {
        let monitor = DiskSpaceMonitor { _ in 2_000_000_000 }

        XCTAssertEqual(
            try monitor.state(for: URL(fileURLWithPath: "/tmp")),
            .warning(availableBytes: 2_000_000_000)
        )
    }

    func testWarnsBelowFourGigabytesAndReportsReadyAtBoundary() throws {
        let monitor = DiskSpaceMonitor { _ in 3_999_999_999 }
        let readyMonitor = DiskSpaceMonitor { _ in 4_000_000_000 }
        let url = URL(fileURLWithPath: "/tmp")

        XCTAssertEqual(
            try monitor.state(for: url),
            .warning(availableBytes: 3_999_999_999)
        )
        XCTAssertEqual(
            try readyMonitor.state(for: url),
            .ready(availableBytes: 4_000_000_000)
        )
    }
}
