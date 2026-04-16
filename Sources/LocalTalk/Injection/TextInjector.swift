import AppKit
import CoreGraphics

class TextInjector {
    // Injects text at the current cursor position via clipboard + Cmd+V.
    // Saves and restores the previous clipboard contents.
    func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // keyCode 9 = 'v' on all Mac keyboard layouts
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
