import CoreGraphics
import Foundation

// Monitors the fn/Globe key (keyCode 63) via a CGEventTap on flagsChanged events.
// Requires Accessibility permission (covers both listening and posting events).
class FnKeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onDown: () -> Void
    private let onUp: () -> Void
    private var fnWasDown = false

    init(onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        self.onDown = onDown
        self.onUp = onUp
    }

    func start() {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: userInfo
        ) else {
            print("[LocalTalk] Failed to create event tap — grant Accessibility permission")
            return
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(event: CGEvent) -> CGEvent? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == 63 else { return event }  // fn/Globe key only

        let isFnDown = event.flags.contains(.maskSecondaryFn)

        if isFnDown && !fnWasDown {
            fnWasDown = true
            onDown()
            return nil  // suppress to prevent system dictation UI
        } else if !isFnDown && fnWasDown {
            fnWasDown = false
            onUp()
            return nil
        }
        return event
    }
}

private func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passRetained(event)
    }

    if let result = monitor.handle(event: event) {
        return Unmanaged.passRetained(result)
    }
    return nil  // suppress event
}
