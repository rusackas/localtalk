import AppKit

enum AppState {
    case loading(String = "Loading Whisper model…")
    case ready
    case recording
    case processing
    case error(String)
}

class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var spinner: NSProgressIndicator?
    private var statusMenuItem: NSMenuItem!

    init() {
        buildMenu()
        setState(.loading())
    }

    func setState(_ state: AppState) {
        guard let button = statusItem.button else { return }

        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil
        button.image = nil

        switch state {
        case .loading(let message):
            statusItem.length = 26
            let s = NSProgressIndicator(frame: NSRect(x: 5, y: 3, width: 16, height: 16))
            s.style = .spinning
            s.controlSize = .small
            s.startAnimation(nil)
            button.addSubview(s)
            spinner = s
            button.toolTip = "LocalTalk: \(message)"
            setStatusLine(message)

        case .ready:
            statusItem.length = NSStatusItem.variableLength
            button.image = icon("mic", color: .labelColor)
            button.toolTip = "LocalTalk: hold fn to dictate"
            setStatusLine(nil)

        case .recording:
            statusItem.length = NSStatusItem.variableLength
            button.image = icon("mic.fill", color: .systemRed)
            button.toolTip = "LocalTalk: recording…"
            setStatusLine(nil)

        case .processing:
            statusItem.length = NSStatusItem.variableLength
            button.image = icon("waveform", color: .systemOrange)
            button.toolTip = "LocalTalk: transcribing…"
            setStatusLine(nil)

        case .error(let msg):
            statusItem.length = NSStatusItem.variableLength
            button.image = icon("exclamationmark.triangle", color: .systemYellow)
            button.toolTip = "LocalTalk: \(msg)"
            setStatusLine(msg)
        }
    }

    private func setStatusLine(_ text: String?) {
        statusMenuItem.title = text ?? ""
        statusMenuItem.isHidden = (text == nil)
    }

    private func icon(_ name: String, color: NSColor) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = false
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [color]))
        return img?.withSymbolConfiguration(config)
    }

    private func buildMenu() {
        let title = NSMenuItem(title: "LocalTalk", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.isHidden = true
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
