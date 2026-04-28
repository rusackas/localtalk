import AppKit

class SettingsWindowController: NSWindowController {
    private var triggerPopUp: NSPopUpButton!
    private var launchAtLoginCheck: NSButton!
    private var soundPopUp: NSPopUpButton!
    private var modelPopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var insertionPopUp: NSPopUpButton!
    private var insertionDescription: NSTextField!
    private var autoCapCheck: NSButton!
    private var trailingPeriodCheck: NSButton!
    private var recordedLabel: NSTextField!
    private var typedLabel: NSTextField!

    var onTriggerChanged: ((TriggerKey) -> Void)?
    var onTranscriptionChanged: (() -> Void)?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
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
        loadFromDefaults()
        updateStats()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadFromDefaults() {
        triggerPopUp.selectItem(at: TriggerKey.presets.firstIndex(of: TriggerKey.load()) ?? 0)
        launchAtLoginCheck.state = LaunchAtLogin.isEnabled ? .on : .off
        soundPopUp.selectItem(at: FeedbackSound.allCases.firstIndex(of: AudioFeedback.selected) ?? 0)
        modelPopUp.selectItem(at: ModelSize.allCases.firstIndex(of: TranscriptionSettings.modelSize) ?? 0)
        languagePopUp.selectItem(at: Language.allCases.firstIndex(of: TranscriptionSettings.language) ?? 0)
        insertionPopUp.selectItem(at: InsertionMode.allCases.firstIndex(of: OutputSettings.insertionMode) ?? 0)
        updateInsertionDescription()
        autoCapCheck.state = OutputSettings.autoCapitalize ? .on : .off
        trailingPeriodCheck.state = OutputSettings.addTrailingPeriod ? .on : .off
    }

    private func updateStats() {
        recordedLabel.stringValue = "Recorded:  \(UsageStats.formattedDuration)"
        typedLabel.stringValue    = "Typed:       \(UsageStats.formattedChars) characters"
    }

    private func updateInsertionDescription() {
        let mode = InsertionMode.allCases[insertionPopUp.indexOfSelectedItem]
        insertionDescription.stringValue = mode.explanation
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // General
        stack.addArrangedSubview(sectionHeader("General"))
        launchAtLoginCheck = NSButton(checkboxWithTitle: "Launch at login",
                                       target: self, action: #selector(toggleLaunchAtLogin))
        stack.addArrangedSubview(launchAtLoginCheck)

        triggerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        TriggerKey.presets.forEach { triggerPopUp.addItem(withTitle: $0.displayName) }
        stack.addArrangedSubview(labeledRow("Hold to record:", control: triggerPopUp))

        soundPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        FeedbackSound.allCases.forEach { soundPopUp.addItem(withTitle: $0.displayName) }
        soundPopUp.target = self
        soundPopUp.action = #selector(soundChanged)
        stack.addArrangedSubview(labeledRow("Sound on start/stop:", control: soundPopUp))

        stack.addArrangedSubview(separator())

        // Transcription
        stack.addArrangedSubview(sectionHeader("Transcription"))
        modelPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        ModelSize.allCases.forEach { modelPopUp.addItem(withTitle: $0.displayName) }
        stack.addArrangedSubview(labeledRow("Model:", control: modelPopUp))

        languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        Language.allCases.forEach { languagePopUp.addItem(withTitle: $0.displayName) }
        stack.addArrangedSubview(labeledRow("Language:", control: languagePopUp))

        let modelNote = NSTextField(wrappingLabelWithString:
            "Switching the model downloads new weights on first use (40 MB – 800 MB).")
        modelNote.font = .systemFont(ofSize: 11)
        modelNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(modelNote)

        stack.addArrangedSubview(separator())

        // Output
        stack.addArrangedSubview(sectionHeader("Output"))
        insertionPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        InsertionMode.allCases.forEach { insertionPopUp.addItem(withTitle: $0.displayName) }
        insertionPopUp.target = self
        insertionPopUp.action = #selector(insertionChanged)
        stack.addArrangedSubview(labeledRow("Insertion mode:", control: insertionPopUp))

        insertionDescription = NSTextField(wrappingLabelWithString: "")
        insertionDescription.font = .systemFont(ofSize: 11)
        insertionDescription.textColor = .secondaryLabelColor
        insertionDescription.preferredMaxLayoutWidth = 380
        stack.addArrangedSubview(insertionDescription)

        autoCapCheck = NSButton(checkboxWithTitle: "Capitalize first letter", target: nil, action: nil)
        stack.addArrangedSubview(autoCapCheck)
        trailingPeriodCheck = NSButton(checkboxWithTitle: "Add trailing period if missing",
                                        target: nil, action: nil)
        stack.addArrangedSubview(trailingPeriodCheck)

        stack.addArrangedSubview(separator())

        // Stats
        stack.addArrangedSubview(sectionHeader("Usage"))
        recordedLabel = NSTextField(labelWithString: "")
        recordedLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(recordedLabel)

        typedLabel = NSTextField(labelWithString: "")
        typedLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(typedLabel)

        let resetBtn = NSButton(title: "Reset Stats", target: self, action: #selector(resetStats))
        resetBtn.bezelStyle = .inline
        stack.addArrangedSubview(resetBtn)

        // Save (with version label on the left)
        let versionLabel = NSTextField(labelWithString: "LocalTalk \(AppUpdater.currentVersion)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let saveRow = NSStackView(views: [versionLabel, spacer, saveBtn])
        saveRow.orientation = .horizontal
        saveRow.distribution = .fill
        saveRow.alignment = .centerY
        stack.addArrangedSubview(saveRow)
        saveRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        return box
    }

    private func labeledRow(_ text: String, control: NSControl) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    // MARK: - Actions

    @objc private func soundChanged() {
        let selected = FeedbackSound.allCases[soundPopUp.indexOfSelectedItem]
        AudioFeedback.preview(selected)
    }

    @objc private func insertionChanged() {
        updateInsertionDescription()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(launchAtLoginCheck.state == .on)
    }

    @objc private func resetStats() {
        UsageStats.reset()
        updateStats()
    }

    @objc private func save() {
        let previousModelName = TranscriptionSettings.modelName

        let trigger = TriggerKey.presets[triggerPopUp.indexOfSelectedItem]
        trigger.save()
        onTriggerChanged?(trigger)

        AudioFeedback.selected = FeedbackSound.allCases[soundPopUp.indexOfSelectedItem]
        TranscriptionSettings.modelSize = ModelSize.allCases[modelPopUp.indexOfSelectedItem]
        TranscriptionSettings.language = Language.allCases[languagePopUp.indexOfSelectedItem]
        OutputSettings.insertionMode = InsertionMode.allCases[insertionPopUp.indexOfSelectedItem]
        OutputSettings.autoCapitalize = autoCapCheck.state == .on
        OutputSettings.addTrailingPeriod = trailingPeriodCheck.state == .on

        if TranscriptionSettings.modelName != previousModelName {
            onTranscriptionChanged?()
        }

        close()
    }
}
