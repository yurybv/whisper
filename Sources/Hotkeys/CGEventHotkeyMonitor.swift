import CoreGraphics
import Foundation

enum HotkeyMonitorError: Error, Equatable, Sendable {
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

    init() {
        let pair = AsyncStream<HotkeyEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        stop()
        continuation.finish()
    }

    func start() throws {
        if lock.withLock({ running }) {
            return
        }

        let eventMask = Self.eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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
    }

    func stop() {
        let state = lock.withLock { () -> (CFRunLoop?, CFMachPort?) in
            running = false
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

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let normalized = Self.normalize(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: isRepeat
        ) {
            continuation.yield(normalized)
        }
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
        monitor.receive(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
