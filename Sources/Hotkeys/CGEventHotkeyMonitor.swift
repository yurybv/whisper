import ApplicationServices
import CoreGraphics
import Foundation

enum HotkeyMonitorError: Error, Equatable, Sendable {
    case accessibilityUnavailable
    case inputMonitoringUnavailable
    case eventTapUnavailable
    case startupTimedOut
}

final class CGEventHotkeyMonitor: HotkeyEventSource, @unchecked Sendable {
    let events: AsyncStream<HotkeyEvent>

    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var eventLoop: CFRunLoop?
    private var eventThread: Thread?
    private var running = false
    private var reservedShortcuts = [ShortcutAction.changeMode, .recordMeeting].compactMap {
        AppSettings.defaults.shortcuts[$0]
    }
    private var consumedKeyCodes: Set<Int> = []
    private let hasListeningAccess: @Sendable () -> Bool
    private let hasAccessibilityAccess: @Sendable () -> Bool

    init(
        hasListeningAccess: @escaping @Sendable () -> Bool = { CGPreflightListenEventAccess() },
        hasAccessibilityAccess: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.hasListeningAccess = hasListeningAccess
        self.hasAccessibilityAccess = hasAccessibilityAccess
        let pair = AsyncStream<HotkeyEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        stop()
        continuation.finish()
    }

    func updateShortcuts(_ shortcuts: [ShortcutAction: Shortcut]) {
        lock.withLock {
            // Mode and meeting commands are always allowed by HotkeyStateMachine.
            // Leave modifier-only dictation and context-dependent Escape untouched.
            reservedShortcuts = [ShortcutAction.changeMode, .recordMeeting].compactMap {
                guard let shortcut = shortcuts[$0],
                      !HotkeyStateMachine.modifierKeyCodes.contains(shortcut.key.keyCode) else { return nil }
                return shortcut
            }
        }
    }

    func start() throws {
        guard hasListeningAccess() else {
            stop()
            throw HotkeyMonitorError.inputMonitoringUnavailable
        }
        guard hasAccessibilityAccess() else {
            stop()
            throw HotkeyMonitorError.accessibilityUnavailable
        }
        if lock.withLock({ running && eventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true }) {
            return
        }
        stop()

        let eventMask = Self.eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: Self.tapOptions,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyMonitorError.eventTapUnavailable
        }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            self?.runEventLoop(ready: ready)
        }
        thread.name = "dev.yury.whisper.hotkeys"
        thread.qualityOfService = .userInteractive

        lock.withLock {
            eventTap = tap
            eventThread = thread
            running = true
        }
        thread.start()

        guard ready.wait(timeout: .now() + 1) == .success else {
            stop()
            throw HotkeyMonitorError.startupTimedOut
        }
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            throw HotkeyMonitorError.eventTapUnavailable
        }
    }

    func stop() {
        let state = lock.withLock { () -> (CFRunLoop?, CFMachPort?) in
            running = false
            consumedKeyCodes.removeAll()
            let state = (eventLoop, eventTap)
            eventLoop = nil
            eventTap = nil
            eventThread = nil
            return state
        }
        if let tap = state.1 {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let eventLoop = state.0 {
            CFRunLoopStop(eventLoop)
        }
    }

    static func normalize(
        type: CGEventType,
        keyCode: Int,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> HotkeyEvent? {
        let modifiers = shortcutModifiers(from: flags)
        switch type {
        case .keyDown:
            return .keyDown(
                keyCode: keyCode,
                flags: modifiers,
                isRepeat: isRepeat
            )
        case .keyUp:
            return .keyUp(keyCode: keyCode, flags: modifiers)
        case .flagsChanged:
            return .flagsChanged(keyCode: keyCode, flags: modifiers)
        default:
            return nil
        }
    }

    static let tapOptions: CGEventTapOptions = .defaultTap

    @discardableResult
    func receive(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let normalized = Self.normalize(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: isRepeat
        ) {
            let shouldSuppress = lock.withLock { () -> Bool in
                switch normalized {
                case let .keyDown(keyCode, flags, isRepeat):
                    if isRepeat { return consumedKeyCodes.contains(keyCode) }
                    // A fresh press also reconciles a release missed while a tap was disabled.
                    consumedKeyCodes.remove(keyCode)
                    guard reservedShortcuts.contains(where: {
                        $0.key.keyCode == keyCode && $0.modifiers == flags
                    }) else { return false }
                    consumedKeyCodes.insert(keyCode)
                    return true
                case let .keyUp(keyCode, _):
                    return consumedKeyCodes.remove(keyCode) != nil
                case .flagsChanged:
                    return false
                }
            }
            continuation.yield(normalized)
            return shouldSuppress
        }
        return false
    }

    fileprivate func reenableEventTap() {
        if let tap = lock.withLock({ eventTap }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func runEventLoop(ready: DispatchSemaphore) {
        guard let tap = lock.withLock({ eventTap }) else {
            ready.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        lock.withLock { eventLoop = runLoop }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()

        if lock.withLock({ running }) {
            CFRunLoopRun()
        }

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
    }

    private static func shortcutModifiers(from flags: CGEventFlags) -> Shortcut.Modifiers {
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        return modifiers
    }

    private static let eventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged
    ]
}

private func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<CGEventHotkeyMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        monitor.reenableEventTap()
    default:
        if monitor.receive(type: type, event: event) { return nil }
    }
    return Unmanaged.passUnretained(event)
}
