import Foundation
import Sparkle

@MainActor
protocol UpdateDriver: AnyObject {
    func start()
    func checkForUpdates()
    func resumeDeferredInstallationIfPossible()
}

@MainActor
final class UpdateInstallationGate {
    private let isBusy: () -> Bool
    private var postponedInstallHandler: (() -> Void)?

    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
    }

    func postponeIfBusy(_ installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        postponedInstallHandler = installHandler
        return true
    }

    func resumeIfPossible() {
        guard !isBusy(), let postponedInstallHandler else { return }
        self.postponedInstallHandler = nil
        postponedInstallHandler()
    }
}

@objc(UpdateController)
@MainActor
final class UpdateController: NSObject {
    private let isReleaseBuild: Bool
    private let isIsolatedLaunch: Bool
    private let driver: any UpdateDriver
    private let isBusy: () -> Bool
    private var hasStarted = false

    init(
        isReleaseBuild: Bool,
        isIsolatedLaunch: Bool,
        driver: any UpdateDriver,
        isBusy: @escaping () -> Bool
    ) {
        self.isReleaseBuild = isReleaseBuild
        self.isIsolatedLaunch = isIsolatedLaunch
        self.driver = driver
        self.isBusy = isBusy
    }

    private var isEnabled: Bool {
        isReleaseBuild && !isIsolatedLaunch
    }

    func start() {
        guard isEnabled, !hasStarted else { return }
        hasStarted = true
        driver.start()
    }

    func checkForUpdates() {
        guard isEnabled else { return }
        driver.checkForUpdates()
    }

    func shouldDeferInstallation() -> Bool {
        isBusy()
    }

    func activityDidChange() {
        guard isEnabled, !isBusy() else { return }
        driver.resumeDeferredInstallationIfPossible()
    }
}

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver, SPUUpdaterDelegate {
    private let installationGate: UpdateInstallationGate
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(isBusy: @escaping () -> Bool) {
        installationGate = UpdateInstallationGate(isBusy: isBusy)
        super.init()
    }

    func start() {
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func resumeDeferredInstallationIfPossible() {
        installationGate.resumeIfPossible()
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        installationGate.postponeIfBusy(installHandler)
    }
}
