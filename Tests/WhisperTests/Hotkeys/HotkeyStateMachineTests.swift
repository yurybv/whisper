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

    func testChangeModeUsesControlCommandMAndIgnoresLegacyFinderShortcut() {
        var machine = HotkeyStateMachine(shortcuts: AppSettings.defaults.shortcuts)
        let flags: Shortcut.Modifiers = [.control, .command]

        XCTAssertEqual(
            machine.consume(
                .keyDown(keyCode: Shortcut.Key.m.keyCode, flags: flags, isRepeat: false)
            ),
            .invoked(.changeMode)
        )
        XCTAssertNil(
            machine.consume(
                .keyDown(keyCode: Shortcut.Key.m.keyCode, flags: flags, isRepeat: true)
            )
        )
        XCTAssertNil(
            machine.consume(.keyUp(keyCode: Shortcut.Key.m.keyCode, flags: flags))
        )
        XCTAssertNil(
            machine.consume(
                .keyDown(keyCode: 40, flags: [.command, .shift], isRepeat: false)
            )
        )
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
    func testFailedPermissionRefreshCanRecoverWithoutLosingActionStream() async throws {
        let source = FakeHotkeyEventSource()
        let monitor = GlobalHotkeyMonitor(source: source, shortcuts: AppSettings.defaults.shortcuts)
        try await monitor.start()
        source.startFailure = .inputMonitoringUnavailable
        do {
            try await monitor.start()
            XCTFail("Revoked listening access must not report a successful refresh")
        } catch {
            XCTAssertEqual(error as? HotkeyMonitorError, .inputMonitoringUnavailable)
        }
        source.startFailure = nil
        try await monitor.start()
        let received = expectation(description: "Action stream remains usable after permission recovery")
        let reader = Task {
            for await action in monitor.actionEvents {
                XCTAssertEqual(action, .invoked(.changeMode))
                received.fulfill()
                return
            }
        }
        source.send(
            .keyDown(
                keyCode: Shortcut.Key.m.keyCode,
                flags: [.control, .command],
                isRepeat: false
            )
        )
        await fulfillment(of: [received], timeout: 2)
        reader.cancel()
        XCTAssertEqual(source.startCount, 3)
        await monitor.stop()
    }


    func testRefreshRechecksSourceWithoutReplacingEventConsumer() async throws {
        let source = FakeHotkeyEventSource()
        let monitor = GlobalHotkeyMonitor(source: source, shortcuts: AppSettings.defaults.shortcuts)
        var actions = monitor.actionEvents.makeAsyncIterator()
        try await monitor.start()
        try await monitor.start()
        XCTAssertEqual(source.startCount, 2, "Permission refresh must let the source recover a disabled tap")
        source.send(
            .keyDown(
                keyCode: Shortcut.Key.m.keyCode,
                flags: [.control, .command],
                isRepeat: false
            )
        )
        let action = await actions.next()
        XCTAssertEqual(action, .invoked(.changeMode))
        await monitor.stop()
    }

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
            shortcuts: [
                .changeMode: Shortcut(key: .k, modifiers: [.command, .shift])
            ]
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
    func testFreshPressReconcilesAReleaseMissedWhileTapWasDisabled() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = [.maskControl, .maskCommand]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        event.flags = []
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        XCTAssertFalse(source.receive(type: .keyUp, event: event))
    }

    func testStopDiscardsAnUnreleasedCommandBeforeRecovery() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = [.maskControl, .maskCommand]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        source.stop()
        event.flags = []
        XCTAssertFalse(source.receive(type: .keyUp, event: event), "Stop itself clears the outstanding claim")
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        XCTAssertFalse(source.receive(type: .keyUp, event: event))
    }

    func testRepeatCannotStartConsumingAPressThatWasPassedThrough() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = []
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        event.flags = [.maskControl, .maskCommand]
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        XCTAssertFalse(source.receive(type: .keyUp, event: event))
    }

    func testMissingAccessibilityFailsBeforeInstallingAnActiveTap() {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { true }, hasAccessibilityAccess: { false })
        XCTAssertThrowsError(try source.start()) { error in
            XCTAssertEqual(error as? HotkeyMonitorError, .accessibilityUnavailable)
        }
        source.stop()
    }

    func testReassignedShortcutConsumesNewBindingAndFinishesOldRelease() async throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let monitor = GlobalHotkeyMonitor(source: source, shortcuts: AppSettings.defaults.shortcuts)
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = [.maskControl, .maskCommand]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        await monitor.updateShortcuts([.changeMode: Shortcut(key: Shortcut.Key(35), modifiers: [.control])])
        XCTAssertTrue(source.receive(type: .keyUp, event: event))
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        _ = source.receive(type: .keyUp, event: event)
        event.setIntegerValueField(.keyboardEventKeycode, value: 35)
        event.flags = .maskControl
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        XCTAssertTrue(source.receive(type: .keyUp, event: event))
        await monitor.resetShortcutsToDefaults()
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
        event.setIntegerValueField(.keyboardEventKeycode, value: 46)
        event.flags = [.maskControl, .maskCommand]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
    }

    func testInitialShortcutConfigurationReplacesDefaults() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let monitor = GlobalHotkeyMonitor(source: source, shortcuts: [:])
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = [.maskControl, .maskCommand]
        withExtendedLifetime(monitor) {
            XCTAssertFalse(source.receive(type: .keyDown, event: event))
        }
    }

    func testNativeTapCanConsumeWhisperCommands() {
        XCTAssertEqual(CGEventHotkeyMonitor.tapOptions, .defaultTap)
    }

    func testModeShortcutIsConsumedButStillPublished() async throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        var events = source.events.makeAsyncIterator()
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 46, keyDown: true)
        )
        event.flags = [.maskControl, .maskCommand]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        let received = await events.next()
        XCTAssertEqual(
            received,
            .keyDown(keyCode: 46, flags: [.control, .command], isRepeat: false)
        )
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        event.flags = []
        XCTAssertTrue(source.receive(type: .keyUp, event: event), "Release stays consumed even after modifiers are released")
        XCTAssertFalse(source.receive(type: .keyUp, event: event), "An unmatched release must pass through")
    }

    func testMeetingShortcutIsConsumed() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 15, keyDown: true))
        event.flags = [.maskCommand, .maskShift]
        XCTAssertTrue(source.receive(type: .keyDown, event: event))
        XCTAssertTrue(source.receive(type: .keyUp, event: event))
    }

    func testUnrelatedKeysAndModifiersPassThrough() throws {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: true))
        for flags: CGEventFlags in [[], .maskCommand, [.maskCommand, .maskShift, .maskAlternate]] {
            event.flags = flags
            XCTAssertFalse(source.receive(type: .keyDown, event: event))
            XCTAssertFalse(source.receive(type: .keyUp, event: event))
        }
        event.setIntegerValueField(.keyboardEventKeycode, value: 61)
        event.flags = .maskAlternate
        XCTAssertFalse(source.receive(type: .flagsChanged, event: event))
        event.setIntegerValueField(.keyboardEventKeycode, value: 53)
        event.flags = []
        XCTAssertFalse(source.receive(type: .keyDown, event: event))
    }

    func testMissingListeningAccessFailsBeforeCreatingAnEventTap() {
        let source = CGEventHotkeyMonitor(hasListeningAccess: { false })
        XCTAssertThrowsError(try source.start()) { error in
            XCTAssertEqual(error as? HotkeyMonitorError, .inputMonitoringUnavailable)
        }
    }

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
    private var storedStartFailure: HotkeyMonitorError?
    var startFailure: HotkeyMonitorError? {
        get { lock.withLock { storedStartFailure } }
        set { lock.withLock { storedStartFailure = newValue } }
    }

    var startCount: Int { lock.withLock { storedStartCount } }
    var stopCount: Int { lock.withLock { storedStopCount } }

    init() {
        let pair = AsyncStream<HotkeyEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func updateShortcuts(_ shortcuts: [ShortcutAction: Shortcut]) {}

    func start() throws {
        let failure = lock.withLock {
            storedStartCount += 1
            return storedStartFailure
        }
        if let failure { throw failure }
    }

    func stop() {
        lock.withLock { storedStopCount += 1 }
    }

    func send(_ event: HotkeyEvent) {
        continuation.yield(event)
    }
}
