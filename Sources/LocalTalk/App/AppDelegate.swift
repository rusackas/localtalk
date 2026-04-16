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

        statusBar = StatusBarController()

        requestPermissions()

        Task { @MainActor in
            statusBar.setState(.loading("Loading Whisper model…"))

            // After a few seconds, hint that a download might be in progress
            let downloadHint = Task { @MainActor in
                try await Task.sleep(for: .seconds(4))
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

        fnMonitor = FnKeyMonitor(
            onDown: { [weak self] in self?.handleFnDown() },
            onUp:   { [weak self] in self?.handleFnUp() }
        )
        fnMonitor.start()
    }

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
            } catch {
                // silent on transcription errors
            }
            statusBar.setState(.ready)
        }
    }

    private func requestPermissions() {
        // Accessibility — covers event tap and CGEvent injection
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        // Microphone
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
}
