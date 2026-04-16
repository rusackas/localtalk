import CoreGraphics
import Foundation

// Monitors a configurable trigger key via a CGEventTap.
// Requires Accessibility permission.
class KeyMonitor {
    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onDown: () -> Void
    private let onUp: () -> Void
    private var keyWasDown = false
    fileprivate var trigger: TriggerKey

    init(trigger: TriggerKey, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        self.trigger = trigger
        self.onDown = onDown
        self.onUp = onUp
    }

    // Returns false if the event tap could not be created (Accessibility not granted).
    @discardableResult
    func start() -> Bool {
        let eventMask: CGEventMask
        switch trigger.mode {
        case .flagsChanged:
            eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        case .keyCombo:
            eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
        }
        let userInfo = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyMonitorCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    func updateTrigger(_ newTrigger: TriggerKey) {
        keyWasDown = false
        trigger = newTrigger
    }

    fileprivate func handle(event: CGEvent, type: CGEventType) -> CGEvent? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch trigger.mode {
        case .flagsChanged:
            guard type == .flagsChanged, keyCode == trigger.keyCode else { return event }
            let isDown = event.flags.rawValue & trigger.flagsValue != 0
            if isDown && !keyWasDown {
                keyWasDown = true
                onDown()
                return nil
            } else if !isDown && keyWasDown {
                keyWasDown = false
                onUp()
                return nil
            }

        case .keyCombo:
            guard (type == .keyDown || type == .keyUp), keyCode == trigger.keyCode else { return event }
            let required = CGEventFlags(rawValue: trigger.flagsValue)
            guard trigger.flagsValue == 0 || event.flags.contains(required) else { return event }
            if type == .keyDown && !keyWasDown {
                keyWasDown = true
                onDown()
                return nil
            } else if type == .keyUp && keyWasDown {
                keyWasDown = false
                onUp()
                return nil
            }
        }
        return event
    }
}

private func keyMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passRetained(event)
    }

    if let result = monitor.handle(event: event, type: type) {
        return Unmanaged.passRetained(result)
    }
    return nil
}
