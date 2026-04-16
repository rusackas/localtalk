import AppKit

class SettingsWindowController: NSWindowController {
    private var popUp: NSPopUpButton!
    private var recordedLabel: NSTextField!
    private var typedLabel: NSTextField!
    var onTriggerChanged: ((TriggerKey) -> Void)?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 210),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "LocalTalk Settings"
        panel.isFloatingPanel = true
        panel.center()
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        let idx = TriggerKey.presets.firstIndex(of: TriggerKey.load()) ?? 0
        popUp.selectItem(at: idx)
        updateStats()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStats() {
        recordedLabel.stringValue = "Recorded:  \(UsageStats.formattedDuration)"
        typedLabel.stringValue    = "Typed:       \(UsageStats.formattedChars) characters"
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Trigger key row
        let triggerLabel = NSTextField(labelWithString: "Hold to record:")
        triggerLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(triggerLabel)

        popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        TriggerKey.presets.forEach { popUp.addItem(withTitle: $0.displayName) }
        popUp.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(popUp)

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sep)

        // Stats
        recordedLabel = NSTextField(labelWithString: "")
        recordedLabel.textColor = .secondaryLabelColor
        recordedLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(recordedLabel)

        typedLabel = NSTextField(labelWithString: "")
        typedLabel.textColor = .secondaryLabelColor
        typedLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(typedLabel)

        let resetBtn = NSButton(title: "Reset Stats", target: self, action: #selector(resetStats))
        resetBtn.bezelStyle = .inline
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(resetBtn)

        // Save button
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(saveBtn)

        NSLayoutConstraint.activate([
            triggerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            triggerLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),

            popUp.leadingAnchor.constraint(equalTo: triggerLabel.trailingAnchor, constant: 12),
            popUp.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            popUp.centerYAnchor.constraint(equalTo: triggerLabel.centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            sep.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            sep.topAnchor.constraint(equalTo: triggerLabel.bottomAnchor, constant: 16),

            recordedLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            recordedLabel.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 12),

            typedLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            typedLabel.topAnchor.constraint(equalTo: recordedLabel.bottomAnchor, constant: 4),

            resetBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            resetBtn.centerYAnchor.constraint(equalTo: typedLabel.centerYAnchor),

            saveBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            saveBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    @objc private func resetStats() {
        UsageStats.reset()
        updateStats()
    }

    @objc private func save() {
        let selected = TriggerKey.presets[popUp.indexOfSelectedItem]
        selected.save()
        onTriggerChanged?(selected)
        close()
    }
}
