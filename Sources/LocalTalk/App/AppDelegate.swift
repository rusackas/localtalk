import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var keyMonitor: KeyMonitor!
    private var recorder = MicrophoneRecorder()
    private var transcriber = WhisperTranscriber()
    private let injector = TextInjector()
    private lazy var settingsWindow = SettingsWindowController()
    private var recordingStartTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController(
            onCheckForUpdates: { AppUpdater.shared.checkForUpdates() },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )

        AppUpdater.shared.onUpdateFound = { [weak self] version in
            self?.statusBar.showUpdate(version: version)
        }

        Task { @MainActor in
            await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { _ in cont.resume() }
            }
            await ensureAccessibility()
            await recorder.warmUp()
            if !recorder.hasInputDevice {
                // Separate task so the model keeps loading while the alert is up.
                Task { @MainActor in self.showNoMicrophoneAlert() }
            }
            startKeyMonitor()
            await loadModel()
        }

        settingsWindow.onTriggerChanged = { [weak self] newTrigger in
            self?.keyMonitor.updateTrigger(newTrigger)
        }
        settingsWindow.onTranscriptionChanged = { [weak self] in
            Task { @MainActor in await self?.loadModel() }
        }
    }

    // MARK: - Accessibility

    private func ensureAccessibility() async {
        guard !AXIsProcessTrusted() else { return }

        statusBar.setState(.error("Accessibility permission needed"))

        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func startKeyMonitor() {
        let trigger = TriggerKey.load()
        keyMonitor = KeyMonitor(
            trigger: trigger,
            onDown: { [weak self] in self?.handleKeyDown() },
            onUp:   { [weak self] in self?.handleKeyUp() }
        )
        if !keyMonitor.start() {
            statusBar.setState(.error("Accessibility permission needed"))
        }
    }

    // MARK: - Model loading

    private func loadModel() async {
        statusBar.setState(.loading("Loading Whisper model…"))

        let downloadHint = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if !transcriber.isReady {
                statusBar.setState(.loading("Downloading model (first run)…"))
            }
        }

        do {
            try await transcriber.load()
            downloadHint.cancel()
            statusBar.setState(.ready)
        } catch {
            downloadHint.cancel()
            statusBar.setState(.error("Model load failed"))
        }
    }

    // MARK: - Recording

    private func handleKeyDown() {
        guard transcriber.isReady, !recorder.isRecording else { return }
        do {
            try recorder.start()
            recordingStartTime = Date()
            AudioFeedback.play()
            DispatchQueue.main.async { self.statusBar.setState(.recording) }
        } catch MicrophoneRecorder.RecorderError.noInputDevice {
            DispatchQueue.main.async {
                self.statusBar.setState(.error("No microphone"))
                self.showNoMicrophoneAlert()
            }
        } catch {
            DispatchQueue.main.async { self.statusBar.setState(.error("Mic error")) }
        }
    }

    private var isShowingNoMicAlert = false

    private func showNoMicrophoneAlert() {
        guard !isShowingNoMicAlert else { return }
        isShowingNoMicAlert = true
        defer { isShowingNoMicAlert = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No microphone detected"
        alert.informativeText = "LocalTalk needs an audio input to transcribe. Connect a microphone or headset, or choose an input device in System Settings → Sound."
        alert.addButton(withTitle: "Open Sound Settings")
        alert.addButton(withTitle: "OK")

        // Accessory (menu bar) apps aren't frontmost, so bring the alert forward.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleKeyUp() {
        guard recorder.isRecording else { return }
        let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        UsageStats.addRecording(seconds: elapsed)

        let samples = recorder.stop()
        AudioFeedback.play()
        DispatchQueue.main.async { self.statusBar.setState(.processing) }

        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(samples: samples)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    injector.inject(trimmed)
                    UsageStats.addCharacters(trimmed.count)
                }
            } catch {}
            statusBar.setState(.ready)
        }
    }
}
