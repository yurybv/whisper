import AppKit
import CoreGraphics
import Foundation

struct AppRuntimeDictationPresentation: Equatable, Sendable {
    let menuState: MenuBarState
    let message: String?
    let recovery: DictationRecovery
    let blocksNewDictation: Bool

    init(state: DictationState) {
        switch state {
        case .idle:
            menuState = .ready
            message = nil
            recovery = .none
            blocksNewDictation = false
        case let .completed(result):
            menuState = .ready
            message = result == .copiedForManualPaste
                ? "Text is on the clipboard. Paste manually."
                : nil
            recovery = .none
            blocksNewDictation = false
        case .recording:
            menuState = .dictating
            message = nil
            recovery = .none
            blocksNewDictation = true
        case .transcribing, .transforming, .inserting:
            menuState = .processing
            message = nil
            recovery = .none
            blocksNewDictation = true
        case let .failed(error, _, recovery):
            menuState = .error
            message = error
            self.recovery = recovery
            blocksNewDictation = recovery.canDiscard
        }
    }
}

@MainActor
final class AppRuntime {
    private let persistence: PersistenceController
    private let modeRepository: ModeRepository
    private let recorder: AVAudioEngineRecorder
    private let coordinator: DictationCoordinator
    private let hotkeys: GlobalHotkeyMonitor
    private let hudController = DictationHUDController()
    private let mainWindowController = MainWindowController()

    private var hotkeyTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var lastState: DictationState = .idle
    private var lastLevel: Float = 0
    private var dictationScreen: NSScreen?

    private var modeSwitcherController: ModeSwitcherController!
    private var menuBarController: MenuBarController!
    private var hotkeyRouter: HotkeyActionRouter!
    private var recoveryActionRouter: DictationRecoveryActionRouter!

    init() throws {
        let paths = try AppPaths()
        persistence = try PersistenceController()
        modeRepository = ModeRepository(context: persistence.container.mainContext)
        try modeRepository.seedDefaultMode()
        let history = HistoryRepository(
            context: persistence.container.mainContext,
            appPaths: paths
        )
        recorder = AVAudioEngineRecorder(paths: paths)
        coordinator = DictationCoordinator(
            recorder: recorder,
            openAI: OpenAIClient(
                secureStore: CachingSecureStore(backingStore: KeychainSecureStore())
            ),
            modeProvider: modeRepository,
            history: history,
            insertion: AXTextInsertionService()
        )
        hotkeys = GlobalHotkeyMonitor(
            source: CGEventHotkeyMonitor(),
            shortcuts: AppSettings.defaults.shortcuts
        )

        modeSwitcherController = ModeSwitcherController(
            panel: ModeSwitcherPanel(),
            modesProvider: { [unowned self] in
                (
                    modes: try modeRepository.fetchAll(),
                    activeModeID: try modeRepository.activeMode().id
                )
            },
            activateMode: { [unowned self] id in
                try modeRepository.activate(id)
            },
            onModeActivated: { [weak self] mode in
                self?.menuBarController.setModeName(mode.name)
            },
            onClosed: { [weak self] in
                guard let self else { return }
                Task { await self.hotkeys.setFeatureActive(self.isDictationActive) }
            }
        )
        recoveryActionRouter = DictationRecoveryActionRouter(
            onRetry: { [weak self] in
                await self?.retryFailedDictation()
            },
            onDiscard: { [weak self] in
                await self?.discardFailedDictation()
            },
            setFeatureActive: { [weak self] isActive in
                guard let self else { return }
                await self.hotkeys.setFeatureActive(isActive)
            }
        )
        menuBarController = MenuBarController(
            onToggleDictation: { [weak self] in
                guard let self else { return }
                Task { await self.toggleDictation() }
            },
            onChangeMode: { [weak self] in self?.showModeSwitcher() },
            onRecordMeeting: { [weak self] in self?.showMeetingStub() },
            onRetryDictation: { [weak self] in self?.recoveryActionRouter.scheduleRetry() },
            onDiscardDictation: { [weak self] in self?.recoveryActionRouter.scheduleDiscard() },
            onRecentHistory: { [weak self] in self?.openMainWindow() },
            onOpenMainWindow: { [weak self] in self?.openMainWindow() },
            onQuit: { NSApp.terminate(nil) }
        )
        hotkeyRouter = HotkeyActionRouter(
            onBegin: { [weak self] in
                guard let self else { return }
                await self.beginDictation()
            },
            onFinish: { [weak self] in
                guard let self else { return }
                await self.finishDictation()
            },
            onChangeMode: { [weak self] in self?.showModeSwitcher() },
            onRecordMeeting: { [weak self] in self?.showMeetingStub() },
            onCancel: { [weak self] in
                guard let self else { return false }
                return await self.cancelTopFeature()
            }
        )
    }

    func start() {
        let initialMode = (try? modeRepository.activeMode()) ?? .defaultMode
        menuBarController.render(state: .ready, modeName: initialMode.name)

        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await hotkeys.start()
            } catch {
                menuBarController.render(
                    state: .error,
                    message: "Enable Accessibility to use global shortcuts."
                )
                return
            }
            for await event in hotkeys.actionEvents {
                guard !Task.isCancelled else { return }
                await hotkeyRouter.handle(event)
            }
        }

        stateTask = Task { [weak self] in
            guard let self else { return }
            let states = await coordinator.states()
            for await state in states {
                guard !Task.isCancelled else { return }
                render(state)
            }
        }

        levelTask = Task { [weak self] in
            guard let self else { return }
            let levels = await recorder.levels()
            for await level in levels {
                guard !Task.isCancelled else { return }
                lastLevel = level
                if case .recording = lastState {
                    hudController.render(state: lastState, level: level, screen: dictationScreen)
                }
            }
        }
    }

    func stop() {
        hotkeyTask?.cancel()
        stateTask?.cancel()
        levelTask?.cancel()
        hotkeyTask = nil
        stateTask = nil
        levelTask = nil
        hotkeyRouter.stop()
        recoveryActionRouter.stop()
        Task { await hotkeys.stop() }
    }

    func hideMainWindow() {
        mainWindowController.hide()
    }

    func openMainWindow() {
        menuBarController.closePopover()
        mainWindowController.show()
    }

#if DEBUG
    func showModeSwitcherForTesting() {
        showModeSwitcher()
    }

    func showHUDForTesting() {
        stateTask?.cancel()
        hudController.render(
            status: .listening(modeName: "Default"),
            level: 0.65,
            screen: NSScreen.screens.first
        )
    }
#endif

    private var isDictationActive: Bool {
        switch lastState {
        case .idle, .completed, .failed: false
        case .recording, .transcribing, .transforming, .inserting: true
        }
    }

    private func toggleDictation() async {
        menuBarController.closePopover()
        if case .recording = lastState {
            hotkeyRouter.scheduleFinish()
        } else if !AppRuntimeDictationPresentation(state: lastState).blocksNewDictation {
            await beginDictation()
        }
    }

    private func beginDictation() async {
        guard !AppRuntimeDictationPresentation(state: lastState).blocksNewDictation else { return }
        dictationScreen = TargetScreenResolver.screenForFrontmostApplication()
        do {
            try await coordinator.begin()
            await hotkeys.setFeatureActive(true)
        } catch {
            menuBarController.render(
                state: .error,
                message: DictationErrorPresentation.message(for: error, recovery: .none)
            )
        }
    }

    private func finishDictation() async {
        await coordinator.finish()
        guard !Task.isCancelled else { return }
        await hotkeys.setFeatureActive(false)
    }

    private func retryFailedDictation() async {
        menuBarController.closePopover()
        do {
            try await coordinator.retry()
        } catch {
            menuBarController.render(
                state: .error,
                message: DictationErrorPresentation.message(for: error, recovery: .none)
            )
        }
    }

    private func discardFailedDictation() async {
        menuBarController.closePopover()
        await coordinator.discardFailed()
    }

    private func cancelTopFeature() async -> Bool {
        if modeSwitcherController.isVisible {
            modeSwitcherController.close()
            return false
        }
        guard isDictationActive else { return false }
        guard await coordinator.cancel() else { return false }
        hudController.render(status: .cancelled, screen: dictationScreen)
        await hotkeys.setFeatureActive(false)
        return true
    }

    private func showModeSwitcher() {
        menuBarController.closePopover()
        do {
            try modeSwitcherController.show()
            Task { await hotkeys.setFeatureActive(true) }
        } catch {
            menuBarController.render(state: .error, message: error.localizedDescription)
        }
    }

    private func showMeetingStub() {
        menuBarController.closePopover()
        menuBarController.render(
            state: .error,
            message: "Meeting recording arrives in the next milestone."
        )
        hudController.render(
            status: .error(
                message: "Meeting recording arrives in the next milestone.",
                textOnClipboard: false
            )
        )
    }

    private func render(_ state: DictationState) {
        lastState = state
        hudController.render(state: state, level: lastLevel, screen: dictationScreen)
        if case let .recording(modeName) = state {
            menuBarController.setModeName(modeName)
        }
        let presentation = AppRuntimeDictationPresentation(state: state)
        menuBarController.render(
            state: presentation.menuState,
            message: presentation.message,
            dictationRecovery: presentation.recovery
        )
    }

}

enum TargetScreenResolver {
    @MainActor
    static func screenForFrontmostApplication() -> NSScreen? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return NSScreen.main ?? NSScreen.screens.first
        }

        let candidateBounds = windowInfo.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else {
                return nil
            }
            return rect
        }
        .max { $0.width * $0.height < $1.width * $1.height }

        guard let candidateBounds else { return NSScreen.main ?? NSScreen.screens.first }
        let point = CGPoint(x: candidateBounds.midX, y: candidateBounds.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
