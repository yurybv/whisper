import CoreGraphics
import XCTest
@testable import Whisper

final class HotkeyStateMachineTests: XCTestCase {
    func testRightOptionProducesPressThenRelease() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)

        XCTAssertEqual(
            machine.consume(.flagsChanged(keyCode: 61, flags: [.option])),
            .pressed(.pushToTalk)
        )
        XCTAssertEqual(
            machine.consume(.flagsChanged(keyCode: 61, flags: [])),
            .released(.pushToTalk)
        )
    }

    func testLeftOptionDoesNotTriggerRightOptionShortcut() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)

        XCTAssertNil(machine.consume(.flagsChanged(keyCode: 58, flags: [.option])))
    }

    func testRepeatedModifierTransitionsEmitOnlyOnce() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)

        XCTAssertEqual(
            machine.consume(.flagsChanged(keyCode: 61, flags: [.option])),
            .pressed(.pushToTalk)
        )
        XCTAssertNil(machine.consume(.flagsChanged(keyCode: 61, flags: [.option])))
        XCTAssertEqual(
            machine.consume(.flagsChanged(keyCode: 61, flags: [])),
            .released(.pushToTalk)
        )
        XCTAssertNil(machine.consume(.flagsChanged(keyCode: 61, flags: [])))
    }

    func testChangeModeInvokesOnlyOnInitialKeyDown() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
        let flags: Shortcut.Modifiers = [.command, .shift]

        XCTAssertEqual(
            machine.consume(.keyDown(keyCode: 40, flags: flags, isRepeat: false)),
            .invoked(.changeMode)
        )
        XCTAssertNil(machine.consume(.keyDown(keyCode: 40, flags: flags, isRepeat: true)))
        XCTAssertNil(machine.consume(.keyUp(keyCode: 40, flags: flags)))
    }

    func testRecordMeetingInvokesOnConfiguredKeyDown() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)

        XCTAssertEqual(
            machine.consume(
                .keyDown(
                    keyCode: Shortcut.Key.r.keyCode,
                    flags: [.command, .shift],
                    isRepeat: false
                )
            ),
            .invoked(.recordMeeting)
        )
    }

    func testEscapeInvokesCancelOnlyWhileFeatureIsActive() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
        let escape = HotkeyEvent.keyDown(
            keyCode: Shortcut.Key.escape.keyCode,
            flags: [],
            isRepeat: false
        )

        XCTAssertNil(machine.consume(escape))

        machine.setFeatureActive(true)

        XCTAssertEqual(machine.consume(escape), .invoked(.cancel))
    }

    func testMeetingDisablesPushToTalk() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
        machine.setMeetingActive(true)

        XCTAssertNil(machine.consume(.flagsChanged(keyCode: 61, flags: [.option])))
        XCTAssertNil(machine.consume(.flagsChanged(keyCode: 61, flags: [])))
    }

    func testStandardKeyPushToTalkProducesPressAndRelease() {
        let pushToTalk = Shortcut(key: Shortcut.Key(35), modifiers: [.control])
        var shortcuts = AppSettings.defaults.shortcuts
        shortcuts[.pushToTalk] = pushToTalk
        var machine = HotkeyStateMachine(shortcuts: shortcuts)

        XCTAssertEqual(
            machine.consume(.keyDown(keyCode: 35, flags: [.control], isRepeat: false)),
            .pressed(.pushToTalk)
        )
        XCTAssertNil(
            machine.consume(.keyDown(keyCode: 35, flags: [.control], isRepeat: true))
        )
        XCTAssertEqual(
            machine.consume(.keyUp(keyCode: 35, flags: [.control])),
            .released(.pushToTalk)
        )
    }

    func testResetRestoresApprovedDefaults() {
        var machine = HotkeyStateMachine(
            shortcuts: [
                .pushToTalk: Shortcut(key: Shortcut.Key(35), modifiers: [.control])
            ]
        )

        machine.resetToDefaults()

        XCTAssertEqual(machine.shortcuts, AppSettings.defaults.shortcuts)
    }

    func testConflictDetectorRejectsDuplicateShortcut() {
        let existing = AppSettings.defaults.shortcuts

        XCTAssertEqual(
            ShortcutConflictDetector.conflict(
                for: existing[.recordMeeting]!,
                action: .changeMode,
                existing: existing
            ),
            .duplicate(.recordMeeting)
        )
    }

    func testConflictDetectorIgnoresShortcutBeingReplaced() {
        let existing = AppSettings.defaults.shortcuts

        XCTAssertNil(
            ShortcutConflictDetector.conflict(
                for: existing[.changeMode]!,
                action: .changeMode,
                existing: existing
            )
        )
    }

    func testConflictDetectorRejectsReservedSystemShortcuts() {
        for keyCode in [12, 13, 4, 46] {
            XCTAssertEqual(
                ShortcutConflictDetector.conflict(
                    for: Shortcut(key: Shortcut.Key(keyCode), modifiers: [.command]),
                    action: .changeMode,
                    existing: [:]
                ),
                .systemReserved
            )
        }
    }

    func testConflictDetectorRejectsUnmodifiedPrintableKey() {
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(
                for: Shortcut(key: .k, modifiers: []),
                action: .changeMode,
                existing: [:]
            ),
            .unmodifiedPrintable
        )
    }

    func testConflictDetectorAllowsEscapeAndModifiedKey() {
        XCTAssertNil(
            ShortcutConflictDetector.conflict(
                for: Shortcut(key: .escape, modifiers: []),
                action: .cancel,
                existing: [:]
            )
        )
        XCTAssertNil(
            ShortcutConflictDetector.conflict(
                for: Shortcut(key: .k, modifiers: [.command, .shift]),
                action: .changeMode,
                existing: [:]
            )
        )
    }

    func testShortcutCaptureRecordsModifierOnlyKey() {
        var capture = ShortcutCaptureStateMachine()
        capture.beginCapture()

        XCTAssertEqual(
            capture.consume(.flagsChanged(keyCode: 61, flags: [.option])),
            Shortcut(key: .rightOption, modifiers: [.option])
        )
        XCTAssertFalse(capture.isCapturing)
    }

    func testShortcutCaptureRecordsStandardCombinationAndSuppressesRepeat() {
        var capture = ShortcutCaptureStateMachine()
        capture.beginCapture()

        XCTAssertNil(
            capture.consume(
                .keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: true)
            )
        )
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(
            capture.consume(
                .keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: false)
            ),
            Shortcut(key: .k, modifiers: [.command, .shift])
        )
        XCTAssertFalse(capture.isCapturing)
    }

    func testShortcutCaptureIgnoresEventsUntilStartedAndCanCancel() {
        var capture = ShortcutCaptureStateMachine()

        XCTAssertNil(
            capture.consume(.keyDown(keyCode: 40, flags: [.command], isRepeat: false))
        )

        capture.beginCapture()
        capture.cancelCapture()

        XCTAssertFalse(capture.isCapturing)
        XCTAssertNil(
            capture.consume(.keyDown(keyCode: 40, flags: [.command], isRepeat: false))
        )
    }
}

final class GlobalHotkeyMonitorTests: XCTestCase {
    func testMonitorStartsSourceAndPublishesNormalizedActions() async throws {
        let source = FakeHotkeyEventSource()
        let monitor = GlobalHotkeyMonitor(
            source: source,
            shortcuts: AppSettings.defaults.shortcuts
        )
        var actions = monitor.actionEvents.makeAsyncIterator()

        try await monitor.start()
        source.send(.flagsChanged(keyCode: 61, flags: [.option]))
        source.send(.flagsChanged(keyCode: 61, flags: []))

        let pressed = await actions.next()
        let released = await actions.next()
        XCTAssertEqual(pressed, .pressed(.pushToTalk))
        XCTAssertEqual(released, .released(.pushToTalk))
        XCTAssertEqual(source.startCount, 1)

        await monitor.stop()

        XCTAssertEqual(source.stopCount, 1)
    }

    func testShortcutCaptureConsumesRawEventBeforeActionDispatch() async throws {
        let source = FakeHotkeyEventSource()
        let monitor = GlobalHotkeyMonitor(
            source: source,
            shortcuts: AppSettings.defaults.shortcuts
        )
        var actions = monitor.actionEvents.makeAsyncIterator()
        var captures = monitor.shortcutCaptures.makeAsyncIterator()

        try await monitor.start()
        await monitor.beginShortcutCapture(for: .changeMode)
        source.send(
            .keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: false)
        )

        let captured = await captures.next()
        XCTAssertEqual(
            captured,
            CapturedShortcut(
                action: .changeMode,
                shortcut: Shortcut(key: .k, modifiers: [.command, .shift])
            )
        )

        source.send(
            .keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: false)
        )
        let invoked = await actions.next()
        XCTAssertEqual(invoked, .invoked(.changeMode))

        await monitor.stop()
    }

    func testMonitorUpdatesContextAndResetsShortcuts() async throws {
        let source = FakeHotkeyEventSource()
        let monitor = GlobalHotkeyMonitor(
            source: source,
            shortcuts: [
                .pushToTalk: Shortcut(key: Shortcut.Key(35), modifiers: [.control])
            ]
        )
        var actions = monitor.actionEvents.makeAsyncIterator()

        try await monitor.start()
        await monitor.resetShortcutsToDefaults()
        await monitor.setMeetingActive(false)
        source.send(.flagsChanged(keyCode: 61, flags: [.option]))

        let pressed = await actions.next()
        XCTAssertEqual(pressed, .pressed(.pushToTalk))

        await monitor.stop()
    }
}

final class CGEventHotkeyMonitorTests: XCTestCase {
    func testNormalizerMapsKeyboardEventsAndSupportedFlags() {
        XCTAssertEqual(
            CGEventHotkeyMonitor.normalize(
                type: .keyDown,
                keyCode: 40,
                flags: [.maskCommand, .maskShift],
                isRepeat: false
            ),
            .keyDown(
                keyCode: 40,
                flags: [.command, .shift],
                isRepeat: false
            )
        )
        XCTAssertEqual(
            CGEventHotkeyMonitor.normalize(
                type: .keyUp,
                keyCode: 40,
                flags: [.maskCommand],
                isRepeat: false
            ),
            .keyUp(keyCode: 40, flags: [.command])
        )
        XCTAssertEqual(
            CGEventHotkeyMonitor.normalize(
                type: .flagsChanged,
                keyCode: 61,
                flags: [.maskAlternate],
                isRepeat: false
            ),
            .flagsChanged(keyCode: 61, flags: [.option])
        )
    }

    func testNormalizerIgnoresUnsupportedEventTypesAndFlags() {
        XCTAssertNil(
            CGEventHotkeyMonitor.normalize(
                type: .leftMouseDown,
                keyCode: 0,
                flags: [.maskAlphaShift],
                isRepeat: false
            )
        )
    }
}

private final class FakeHotkeyEventSource: HotkeyEventSource, @unchecked Sendable {
    let events: AsyncStream<HotkeyEvent>
    private let continuation: AsyncStream<HotkeyEvent>.Continuation
    private let lock = NSLock()
    private var storedStartCount = 0
    private var storedStopCount = 0

    var startCount: Int { lock.withLock { storedStartCount } }
    var stopCount: Int { lock.withLock { storedStopCount } }

    init() {
        let pair = AsyncStream<HotkeyEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start() throws {
        lock.withLock { storedStartCount += 1 }
    }

    func stop() {
        lock.withLock { storedStopCount += 1 }
    }

    func send(_ event: HotkeyEvent) {
        continuation.yield(event)
    }
}
