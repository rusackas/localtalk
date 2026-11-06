import AppKit
import CoreGraphics

@MainActor
class TextInjector {
    func inject(_ text: String) async {
        let transformed = OutputSettings.transform(text)
        switch OutputSettings.insertionMode {
        case .paste: injectViaPaste(transformed)
        // Live mode types phrases itself as they're confirmed (see LiveDictation);
        // anything routed through here in that mode is just typed.
        case .type, .live: await type(transformed)
        }
    }

    // Paste via clipboard + Cmd+V. Saves and restores the previous clipboard,
    // including non-text contents (images, files, rich text), which used to be
    // wiped because only the plain-string flavor was saved.
    private func injectViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        postCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            // If something else was copied in the meantime, leave it alone.
            guard pasteboard.changeCount == ourChangeCount else { return }
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                pasteboard.writeObjects(previousItems)
            }
        }
    }

    /// Gap between synthesized keystrokes. Some apps (Electron, some web editors)
    /// drop or reorder characters when events arrive back-to-back. Async sleep
    /// rather than usleep so the main thread (and the trigger-key event tap on
    /// it) stays responsive while long text is typed.
    private static let keystrokeInterval: Duration = .milliseconds(2)

    // Synthesize keystrokes so each character lands as if typed. Works in a few
    // fields that reject paste, but is slower and can interleave with user input.
    func type(_ text: String) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let chunks = Self.keystrokeChunks(text)
        for (index, chunk) in chunks.enumerated() {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            // Live mode types while the trigger key (fn / Option / Control) is
            // still held; don't let that modifier leak onto the typed characters.
            down.flags = []
            up.flags = []
            chunk.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            if index < chunks.count - 1 {
                try? await Task.sleep(for: Self.keystrokeInterval)
            }
        }
    }

    /// Splits text into the UTF-16 units to post per keystroke. Surrogate pairs
    /// (emoji, other non-BMP characters) must be posted together or they render
    /// as garbage.
    nonisolated static func keystrokeChunks(_ text: String) -> [[UniChar]] {
        let utf16 = Array(text.utf16)
        var chunks: [[UniChar]] = []
        var i = 0
        while i < utf16.count {
            let unit = utf16[i]
            if UTF16.isLeadSurrogate(unit), i + 1 < utf16.count, UTF16.isTrailSurrogate(utf16[i + 1]) {
                chunks.append([unit, utf16[i + 1]])
                i += 2
            } else {
                chunks.append([unit])
                i += 1
            }
        }
        return chunks
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
