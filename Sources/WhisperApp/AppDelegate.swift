import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?
    private var fallbackMenuBar: MenuBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        do {
            let runtime = try AppRuntime()
            self.runtime = runtime
            runtime.start()
            DispatchQueue.main.async {
                runtime.hideMainWindow()
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-smoke-mode-switcher") {
                    runtime.showModeSwitcherForTesting()
                } else if ProcessInfo.processInfo.arguments.contains("--ui-smoke-hud") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        runtime.showHUDForTesting()
                    }
                }
#endif
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
                onRecentHistory: {},
                onOpenMainWindow: {},
                onQuit: { NSApp.terminate(nil) }
            )
            fallbackMenuBar = menu
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }
}
