import AppKit

enum AppState {
    case loading(String = "Loading Whisper model…")
    case ready
    case recording
    case processing
    case error(String)
}

class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var spinner: NSProgressIndicator?
    private var statusMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var checkMenuItem: NSMenuItem!

    init(onCheckForUpdates: @escaping () async -> String?) {
        self.checkAction = onCheckForUpdates
        super.init()
        buildMenu()
        setState(.loading())
    }

    private let checkAction: () async -> String?

    func setState(_ state: AppState) {
        guard let button = statusItem.button else { return }

        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil
        button.image = nil
        settingsMenuItem.isHidden = true

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
            settingsMenuItem.isHidden = !msg.lowercased().contains("accessibility")
        }
    }

    func showUpdate(version: String) {
        updateMenuItem.title = "↑ Update available: v\(version)"
        updateMenuItem.isHidden = false
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openReleasesPage() {
        NSWorkspace.shared.open(UpdateChecker.releasesURL)
    }

    @objc private func checkForUpdates() {
        checkMenuItem.title = "Checking…"
        checkMenuItem.isEnabled = false
        Task { @MainActor in
            if let version = await checkAction() {
                showUpdate(version: version)
                NSWorkspace.shared.open(UpdateChecker.releasesURL)
            } else {
                checkMenuItem.title = "Up to date ✓"
                try? await Task.sleep(for: .seconds(2))
            }
            checkMenuItem.title = "Check for Updates…"
            checkMenuItem.isEnabled = true
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

        settingsMenuItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        settingsMenuItem.target = self
        settingsMenuItem.isHidden = true
        menu.addItem(settingsMenuItem)

        menu.addItem(.separator())

        updateMenuItem = NSMenuItem(title: "", action: #selector(openReleasesPage), keyEquivalent: "")
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        menu.addItem(updateMenuItem)

        checkMenuItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
