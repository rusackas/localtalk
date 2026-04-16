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
            onCheckForUpdates: { await UpdateChecker.availableUpdate() },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )

        Task { @MainActor in
            await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { _ in cont.resume() }
            }
            await ensureAccessibility()
            await recorder.warmUp()
            startKeyMonitor()
            await loadModel()

            if let version = await UpdateChecker.availableUpdate() {
                statusBar.showUpdate(version: version)
            }
        }

        settingsWindow.onTriggerChanged = { [weak self] newTrigger in
            self?.keyMonitor.updateTrigger(newTrigger)
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
            DispatchQueue.main.async { self.statusBar.setState(.recording) }
        } catch {
            DispatchQueue.main.async { self.statusBar.setState(.error("Mic error")) }
        }
    }

    private func handleKeyUp() {
        guard recorder.isRecording else { return }
        let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        UsageStats.addRecording(seconds: elapsed)

        let samples = recorder.stop()
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
