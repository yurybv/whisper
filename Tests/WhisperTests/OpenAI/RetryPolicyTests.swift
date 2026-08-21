import XCTest
@testable import Whisper

final class RetryPolicyTests: XCTestCase {
    private let policy = RetryPolicy()

    func testRetriesOnlyApprovedHTTPStatuses() {
        for statusCode in [429, 500, 502, 503, 504] {
            XCTAssertTrue(policy.shouldRetry(statusCode: statusCode), "Expected retry for \(statusCode)")
        }

        for statusCode in [200, 400, 401, 403, 404] {
            XCTAssertFalse(policy.shouldRetry(statusCode: statusCode), "Unexpected retry for \(statusCode)")
        }
    }

    func testRetriesOnlyApprovedNetworkErrors() {
        for code in [URLError.timedOut, .networkConnectionLost, .notConnectedToInternet] {
            XCTAssertTrue(policy.shouldRetry(error: URLError(code)))
        }

        XCTAssertFalse(policy.shouldRetry(error: URLError(.cancelled)))
        XCTAssertFalse(policy.shouldRetry(error: URLError(.badURL)))
        XCTAssertFalse(policy.shouldRetry(error: CancellationError()))
    }

    func testUsesOneTwoFourSecondBackoffPlusInjectedJitter() {
        XCTAssertEqual(policy.delay(forRetryAttempt: 0, jitter: 0.25), 1.25)
        XCTAssertEqual(policy.delay(forRetryAttempt: 1, jitter: 0.25), 2.25)
        XCTAssertEqual(policy.delay(forRetryAttempt: 2, jitter: 0.25), 4.25)
        XCTAssertNil(policy.delay(forRetryAttempt: 3, jitter: 0.25))
    }
}
