import Foundation
import XCTest
@testable import Whisper

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testUpdateControllerIsAvailableToTheApplication() {
        XCTAssertNotNil(NSClassFromString("Whisper.UpdateController"))
    }

    func testReleaseLaunchStartsOnceAndBothManualActionsUseOneDriver() {
        let driver = FakeUpdateDriver()
        let controller = UpdateController(
            isReleaseBuild: true,
            isIsolatedLaunch: false,
            driver: driver,
            isBusy: { false }
        )

        controller.start()
        controller.start()
        controller.checkForUpdates()
        controller.checkForUpdates()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.checkCount, 2)
    }

    func testDevelopmentAndIsolatedLaunchesDoNotStartOrCheckForUpdates() {
        for configuration in [(false, false), (true, true)] {
            let driver = FakeUpdateDriver()
            let controller = UpdateController(
                isReleaseBuild: configuration.0,
                isIsolatedLaunch: configuration.1,
                driver: driver,
                isBusy: { false }
            )

            controller.start()
            controller.checkForUpdates()

            XCTAssertEqual(driver.startCount, 0)
            XCTAssertEqual(driver.checkCount, 0)
        }
    }

    func testBusyWorkDefersAndIdleWorkResumesInstallation() {
        var busy = true
        var installationCount = 0
        let gate = UpdateInstallationGate(isBusy: { busy })

        XCTAssertTrue(gate.postponeIfBusy { installationCount += 1 })
        gate.resumeIfPossible()
        XCTAssertEqual(installationCount, 0)

        busy = false
        gate.resumeIfPossible()
        XCTAssertEqual(installationCount, 1)

        busy = true
        let driver = FakeUpdateDriver()
        let controller = UpdateController(
            isReleaseBuild: true,
            isIsolatedLaunch: false,
            driver: driver,
            isBusy: { busy }
        )

        XCTAssertTrue(controller.shouldDeferInstallation())
        controller.activityDidChange()
        XCTAssertEqual(driver.resumeCount, 0)

        busy = false
        controller.activityDidChange()
        XCTAssertEqual(driver.resumeCount, 1)
    }

    func testUnavailableFeedDoesNotDisableLaterManualChecks() {
        let driver = FakeUpdateDriver()
        driver.feedAvailable = false
        let controller = UpdateController(
            isReleaseBuild: true,
            isIsolatedLaunch: false,
            driver: driver,
            isBusy: { false }
        )

        controller.checkForUpdates()
        driver.feedAvailable = true
        controller.checkForUpdates()

        XCTAssertEqual(driver.failedCheckCount, 1)
        XCTAssertEqual(driver.checkCount, 2)
    }
}

@MainActor
private final class FakeUpdateDriver: UpdateDriver {
    var startCount = 0
    var checkCount = 0
    var resumeCount = 0
    var failedCheckCount = 0
    var feedAvailable = true

    func start() { startCount += 1 }
    func checkForUpdates() {
        checkCount += 1
        if !feedAvailable {
            failedCheckCount += 1
        }
    }
    func resumeDeferredInstallationIfPossible() { resumeCount += 1 }
}
