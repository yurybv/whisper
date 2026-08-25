import Foundation

protocol HotkeyEventSource: Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    func start() throws
    func stop()
}

struct CapturedShortcut: Equatable, Sendable {
    let action: ShortcutAction
    let shortcut: Shortcut
}

actor GlobalHotkeyMonitor {
    nonisolated let actionEvents: AsyncStream<HotkeyActionEvent>
    nonisolated let shortcutCaptures: AsyncStream<CapturedShortcut>

    private let source: any HotkeyEventSource
    private let actionContinuation: AsyncStream<HotkeyActionEvent>.Continuation
    private let captureContinuation: AsyncStream<CapturedShortcut>.Continuation
    private var stateMachine: HotkeyStateMachine
    private var captureStateMachine = ShortcutCaptureStateMachine()
    private var captureAction: ShortcutAction?
    private var monitoringTask: Task<Void, Never>?

    init(source: any HotkeyEventSource, shortcuts: [ShortcutAction: Shortcut]) {
        self.source = source
        stateMachine = HotkeyStateMachine(shortcuts: shortcuts)

        let actionPair = AsyncStream<HotkeyActionEvent>.makeStream()
        actionEvents = actionPair.stream
        actionContinuation = actionPair.continuation

        let capturePair = AsyncStream<CapturedShortcut>.makeStream()
        shortcutCaptures = capturePair.stream
        captureContinuation = capturePair.continuation
    }

    func start() throws {
        guard monitoringTask == nil else {
            return
        }
        try source.start()
        let events = source.events
        monitoringTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    break
                }
                await self?.consume(event)
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        source.stop()
    }

    func beginShortcutCapture(for action: ShortcutAction) {
        captureAction = action
        captureStateMachine.beginCapture()
    }

    func cancelShortcutCapture() {
        captureAction = nil
        captureStateMachine.cancelCapture()
    }

    func updateShortcuts(_ shortcuts: [ShortcutAction: Shortcut]) {
        stateMachine.updateShortcuts(shortcuts)
    }

    func resetShortcutsToDefaults() {
        stateMachine.resetToDefaults()
    }

    func setFeatureActive(_ isActive: Bool) {
        stateMachine.setFeatureActive(isActive)
    }

    func setMeetingActive(_ isActive: Bool) {
        stateMachine.setMeetingActive(isActive)
    }

    private func consume(_ event: HotkeyEvent) {
        if captureStateMachine.isCapturing {
            guard let shortcut = captureStateMachine.consume(event),
                  let action = captureAction else {
                return
            }
            captureAction = nil
            captureContinuation.yield(
                CapturedShortcut(action: action, shortcut: shortcut)
            )
            return
        }

        if let actionEvent = stateMachine.consume(event) {
            actionContinuation.yield(actionEvent)
        }
    }
}
