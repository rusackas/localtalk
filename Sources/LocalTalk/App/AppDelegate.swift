import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var fnMonitor: FnKeyMonitor!
    private var recorder = MicrophoneRecorder()
    private var transcriber = WhisperTranscriber()
    private let injector = TextInjector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController(onCheckForUpdates: {
            await UpdateChecker.availableUpdate()
        })

        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        Task { @MainActor in
            await ensureAccessibility()
            startFnMonitor()
            await loadModel()

            if let version = await UpdateChecker.availableUpdate() {
                statusBar.showUpdate(version: version)
            }
        }
    }

    // MARK: - Accessibility

    private func ensureAccessibility() async {
        guard !AXIsProcessTrusted() else { return }

        statusBar.setState(.error("Accessibility permission needed"))

        // Show the system prompt (opens Privacy & Security if not trusted)
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        // Poll until the user grants it
        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func startFnMonitor() {
        fnMonitor = FnKeyMonitor(
            onDown: { [weak self] in self?.handleFnDown() },
            onUp:   { [weak self] in self?.handleFnUp() }
        )
        fnMonitor.start()
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

    private func handleFnDown() {
        guard transcriber.isReady, !recorder.isRecording else { return }
        do {
            try recorder.start()
            DispatchQueue.main.async { self.statusBar.setState(.recording) }
        } catch {
            DispatchQueue.main.async { self.statusBar.setState(.error("Mic error")) }
        }
    }

    private func handleFnUp() {
        guard recorder.isRecording else { return }
        let samples = recorder.stop()
        DispatchQueue.main.async { self.statusBar.setState(.processing) }

        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(samples: samples)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    injector.inject(trimmed)
                }
            } catch {}
            statusBar.setState(.ready)
        }
    }
}
