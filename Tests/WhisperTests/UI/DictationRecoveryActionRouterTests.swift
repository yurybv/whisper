import XCTest
@testable import Whisper

@MainActor
final class DictationRecoveryActionRouterTests: XCTestCase {
    func testRecoveryActionsAreSingleFlightAndKeepHotkeysActiveUntilRetryEnds() async {
        let retryStarted = expectation(description: "Retry started")
        let retryFinished = expectation(description: "Retry finished")
        let discardFinished = expectation(description: "Discard finished")
        let retryGate = RecoveryActionGate()
        var events: [String] = []
        let router = DictationRecoveryActionRouter(
            onRetry: {
                events.append("retry")
                retryStarted.fulfill()
                await retryGate.wait()
                retryFinished.fulfill()
            },
            onDiscard: {
                events.append("discard")
                discardFinished.fulfill()
            },
            setFeatureActive: { isActive in
                events.append(isActive ? "hotkeys.active" : "hotkeys.inactive")
            }
        )

        router.scheduleRetry()
        router.scheduleRetry()
        router.scheduleDiscard()
        await fulfillment(of: [retryStarted], timeout: 1)

        XCTAssertEqual(events, ["hotkeys.active", "retry"])
        await retryGate.open()
        await fulfillment(of: [retryFinished], timeout: 1)
        await waitUntilIdle(router)

        XCTAssertEqual(events, ["hotkeys.active", "retry", "hotkeys.inactive"])
        router.scheduleDiscard()
        await fulfillment(of: [discardFinished], timeout: 1)
        await waitUntilIdle(router)
        XCTAssertEqual(
            events,
            ["hotkeys.active", "retry", "hotkeys.inactive", "discard", "hotkeys.inactive"]
        )
    }

    private func waitUntilIdle(_ router: DictationRecoveryActionRouter) async {
        for _ in 0..<100 where router.isRunning {
            await Task.yield()
        }
        XCTAssertFalse(router.isRunning)
    }
}

private actor RecoveryActionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
