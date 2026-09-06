import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?
    private var testModeSwitcher: ModeSwitcherController?
    private var testWindow: MainWindowController?
    private var fallbackMenuBar: MenuBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--ui-smoke-mode-switcher") {
                let mode = ModeDefinition.defaultMode
                let panel = ModeSwitcherPanel()
                // XCTest activates its runner after launch; keep the test panel discoverable.
                panel.hidesOnDeactivate = false
                let switcher = ModeSwitcherController(
                    panel: panel,
                    modesProvider: { ([mode], mode.id) },
                    activateMode: { _ in },
                    onModeActivated: { _ in },
                    onClosed: {}
                )
                testModeSwitcher = switcher
                DispatchQueue.main.async { try? switcher.show() }
                return
            }
            let model = OnboardingTestEnvironment.makeModel(arguments: ProcessInfo.processInfo.arguments)
            let window = MainWindowController(onboarding: model)
            testWindow = window
            window.show()
            return
        }
#endif
        do {
            let runtime = try AppRuntime()
            self.runtime = runtime
            runtime.start()
            DispatchQueue.main.async {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-smoke-mode-switcher") {
                    runtime.showModeSwitcherForTesting()
                    return
                } else if ProcessInfo.processInfo.arguments.contains("--ui-smoke-hud") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        runtime.showHUDForTesting()
                    }
                    return
                }
#endif
                runtime.showInitialWindow()
            }
        } catch {
            let menu = MenuBarController(
                viewModel: MenuBarViewModel(
                    state: .error,
                    message: "Whisper could not initialize its local storage."
                ),
                onToggleDictation: {},
                onChangeMode: {},
                onRecordMeeting: {},
                onRetryDictation: {},
                onDiscardDictation: {},
                onRecentHistory: {},
                onOpenMainWindow: {},
                onQuit: { NSApp.terminate(nil) }
            )
            fallbackMenuBar = menu
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        runtime?.refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }
}
