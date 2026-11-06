import AppKit
import AVFoundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var keyMonitor: KeyMonitor!
    private var recorder = MicrophoneRecorder()
    private var transcriber = WhisperTranscriber()
    private let injector = TextInjector()
    private lazy var settingsWindow = SettingsWindowController()
    private var recordingStartTime: Date?
    // Transcriptions run one at a time, in order, so a dictation started while
    // the previous one is still transcribing can't inject its text first or
    // run WhisperKit concurrently.
    private var transcriptionChain: Task<Void, Never>?
    private var pendingTranscriptions = 0
    private var liveDictation: LiveDictation?

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
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
            await ensureAccessibility()
            await recorder.warmUp()
            // Separate task so the model keeps loading while the alert is up.
            if !micGranted {
                Task { @MainActor in self.reportMicrophoneProblem(.permissionDenied) }
            } else if !recorder.hasInputDevice {
                Task { @MainActor in self.reportMicrophoneProblem(.noDevice) }
            }
            startKeyMonitor()
            await loadModel()
        }

        settingsWindow.onTriggerChanged = { [weak self] newTrigger in
            self?.keyMonitor?.updateTrigger(newTrigger)
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
            if !Task.isCancelled && !transcriber.isReady {
                statusBar.setState(.loading("Downloading model (first run)…"))
            }
        }

        do {
            try await transcriber.load()
            downloadHint.cancel()
            setReadyUnlessBusy()
        } catch {
            downloadHint.cancel()
            statusBar.setState(.error("Model load failed"))
        }
    }

    // MARK: - Recording

    /// Shows the idle mic icon, unless something more specific should stay up: a
    /// model (re)load, a recording in progress, or queued transcriptions.
    /// An outstanding mic problem keeps the warning icon up instead of the mic.
    private func setReadyUnlessBusy() {
        guard transcriber.isReady, !recorder.isRecording, pendingTranscriptions == 0 else { return }
        if let micProblem {
            statusBar.setState(.error(micProblem.statusText))
        } else {
            statusBar.setState(.ready)
        }
    }

    private func handleKeyDown() {
        // Not ready = still loading a model; the key does nothing until the mic
        // icon appears.
        guard transcriber.isReady, !recorder.isRecording else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            return
        default:
            reportMicrophoneProblem(.permissionDenied)
            return
        }

        do {
            try recorder.start()
            clearMicrophoneProblem()
            recordingStartTime = Date()
            AudioFeedback.play()
            statusBar.setState(.recording)
            if Self.wantsLive(mode: OutputSettings.insertionMode,
                              shiftHeld: NSEvent.modifierFlags.contains(.shift),
                              trigger: TriggerKey.load()) {
                let live = LiveDictation(recorder: recorder, transcriber: transcriber, injector: injector)
                live.start(after: transcriptionChain)
                liveDictation = live
            }
        } catch MicrophoneRecorder.RecorderError.noInputDevice {
            reportMicrophoneProblem(.noDevice)
        } catch {
            // One-off failure (e.g. the device vanished mid-start). Flash the
            // warning, then go back to ready; the next key press retries.
            statusBar.setState(.error("Mic error"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                MainActor.assumeIsolated { self?.setReadyUnlessBusy() }
            }
        }
    }

    private enum MicrophoneProblem {
        case noDevice
        case permissionDenied

        var statusText: String {
            switch self {
            case .noDevice: return "No microphone"
            case .permissionDenied: return "Microphone access denied"
            }
        }
    }

    private var micProblem: MicrophoneProblem?
    private var micRecoveryTimer: Timer?

    /// Shows the warning icon and alert, then polls until the problem goes away
    /// (mic plugged in / access granted) so the icon doesn't stay stuck on the
    /// warning until the next dictation.
    private func reportMicrophoneProblem(_ problem: MicrophoneProblem) {
        micProblem = problem
        setReadyUnlessBusy()  // no-op while the model is still loading
        if micRecoveryTimer == nil {
            micRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkMicrophoneRecovered() }
            }
        }
        showMicrophoneAlert(problem)
    }

    private func checkMicrophoneRecovered() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              recorder.hasInputDevice else { return }
        clearMicrophoneProblem()
        setReadyUnlessBusy()
    }

    private func clearMicrophoneProblem() {
        micProblem = nil
        micRecoveryTimer?.invalidate()
        micRecoveryTimer = nil
    }

    private var isShowingMicAlert = false

    private func showMicrophoneAlert(_ problem: MicrophoneProblem) {
        guard !isShowingMicAlert else { return }
        isShowingMicAlert = true
        defer { isShowingMicAlert = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        let settingsURL: String
        switch problem {
        case .noDevice:
            alert.messageText = "No microphone detected"
            alert.informativeText = "LocalTalk needs an audio input to transcribe. Connect a microphone or headset, or choose an input device in System Settings → Sound."
            alert.addButton(withTitle: "Open Sound Settings")
            settingsURL = "x-apple.systempreferences:com.apple.Sound-Settings.extension?input"
        case .permissionDenied:
            alert.messageText = "Microphone access is turned off"
            alert.informativeText = "LocalTalk can't hear you without microphone access. Turn on LocalTalk in System Settings → Privacy & Security → Microphone. You may need to quit and reopen LocalTalk afterwards."
            alert.addButton(withTitle: "Open Privacy Settings")
            settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
        alert.addButton(withTitle: "OK")

        // Accessory (menu bar) apps aren't frontmost, so bring the alert forward.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Live mode is used when it's the chosen output mode, or for this one
    /// dictation when Shift is held as the trigger key goes down. (Not when
    /// the trigger itself is a Shift combo, or every dictation would be live.)
    static func wantsLive(mode: InsertionMode, shiftHeld: Bool, trigger: TriggerKey) -> Bool {
        if mode == .live { return true }
        let triggerUsesShift = CGEventFlags(rawValue: trigger.flagsValue).contains(.maskShift)
        return shiftHeld && !triggerUsesShift
    }

    private func handleKeyUp() {
        guard recorder.isRecording else { return }
        let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        UsageStats.addRecording(seconds: elapsed)

        let samples = recorder.stop()
        AudioFeedback.play()
        statusBar.setState(.processing)

        let live = liveDictation
        liveDictation = nil

        pendingTranscriptions += 1
        let previous = transcriptionChain
        transcriptionChain = Task { @MainActor in
            await previous?.value
            if let live {
                let typed = await live.finish(finalSamples: samples)
                UsageStats.addCharacters(typed.count)
            } else {
                do {
                    let text = try await transcriber.transcribe(samples: samples)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        await injector.inject(trimmed)
                        UsageStats.addCharacters(trimmed.count)
                    }
                } catch {}
            }
            pendingTranscriptions -= 1
            setReadyUnlessBusy()
        }
    }
}
