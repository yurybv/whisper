import XCTest
@testable import Whisper

@MainActor
final class HotkeyActionRouterTests: XCTestCase {
    func testReleaseKeepsCancelResponsiveWhileFinishIsSuspended() async {
        let finishStarted = expectation(description: "Finish started")
        let finishReturned = expectation(description: "Cancelled finish returned")
        let finishGate = AsyncTestGate()
        var cancelCount = 0
        var finishReachedSideEffects = false
        let router = HotkeyActionRouter(
            onBegin: {},
            onFinish: {
                defer { finishReturned.fulfill() }
                finishStarted.fulfill()
                await finishGate.wait()
                guard !Task.isCancelled else { return }
                finishReachedSideEffects = true
            },
            onChangeMode: {},
            onRecordMeeting: {},
            onCancel: {
                cancelCount += 1
                return true
            }
        )

        await router.handle(.released(.pushToTalk))
        await fulfillment(of: [finishStarted], timeout: 1)
        await router.handle(.invoked(.cancel))

        XCTAssertEqual(cancelCount, 1)
        await finishGate.open()
        await fulfillment(of: [finishReturned], timeout: 1)
        XCTAssertFalse(finishReachedSideEffects)
    }

    func testClosingTopPanelDoesNotCancelTheProcessingTask() async {
        let firstFinishStarted = expectation(description: "First finish started")
        let finishGate = AsyncTestGate()
        var finishCount = 0
        let router = HotkeyActionRouter(
            onBegin: {},
            onFinish: {
                finishCount += 1
                guard finishCount == 1 else { return }
                firstFinishStarted.fulfill()
                await finishGate.wait()
            },
            onChangeMode: {},
            onRecordMeeting: {},
            onCancel: { false }
        )

        await router.handle(.released(.pushToTalk))
        await fulfillment(of: [firstFinishStarted], timeout: 1)
        await router.handle(.invoked(.cancel))
        await router.handle(.released(.pushToTalk))
        await Task.yield()

        XCTAssertEqual(finishCount, 1)
        await finishGate.open()
    }
}

private actor AsyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
