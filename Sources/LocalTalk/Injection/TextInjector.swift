import AppKit
import CoreGraphics

class TextInjector {
    func inject(_ text: String) {
        let transformed = OutputSettings.transform(text)
        switch OutputSettings.insertionMode {
        case .paste: injectViaPaste(transformed)
        case .type:  injectViaTyping(transformed)
        }
    }

    // Paste via clipboard + Cmd+V. Saves and restores the previous clipboard.
    private func injectViaPaste(_ text: String) {
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

    // Synthesize keystrokes so each character lands as if typed. Works in a few
    // fields that reject paste, but is slower and can interleave with user input.
    private func injectViaTyping(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(text.utf16)
        var i = 0
        while i < utf16.count {
            // Surrogate pairs must be posted together so emoji/non-BMP render correctly.
            let unit = utf16[i]
            let isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF
            let chunk: [UniChar]
            if isHighSurrogate, i + 1 < utf16.count {
                chunk = [unit, utf16[i + 1]]
                i += 2
            } else {
                chunk = [unit]
                i += 1
            }

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            chunk.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
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
