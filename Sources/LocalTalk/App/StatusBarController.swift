import AppKit

enum AppState {
    case loading
    case ready
    case recording
    case processing
    case error(String)
}

class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init() {
        buildMenu()
        setState(.loading)
    }

    func setState(_ state: AppState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .loading:
            button.image = icon("mic.slash", color: .secondaryLabelColor)
            button.toolTip = "LocalTalk: loading model…"
        case .ready:
            button.image = icon("mic", color: .labelColor)
            button.toolTip = "LocalTalk: hold fn to dictate"
        case .recording:
            button.image = icon("mic.fill", color: .systemRed)
            button.toolTip = "LocalTalk: recording…"
        case .processing:
            button.image = icon("waveform", color: .systemOrange)
            button.toolTip = "LocalTalk: transcribing…"
        case .error(let msg):
            button.image = icon("exclamationmark.triangle", color: .systemYellow)
            button.toolTip = "LocalTalk: \(msg)"
        }
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
