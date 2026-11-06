import AVFoundation

class MicrophoneRecorder {
    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    enum RecorderError: LocalizedError {
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .noInputDevice: return "No usable audio input device"
            case .converterUnavailable: return "Could not create audio converter"
            }
        }
    }

    /// Whether the system currently has a usable default input device.
    var hasInputDevice: Bool { refreshInputNodeIfNeeded() }

    // Call once after mic permission is granted. Primes the converter and format
    // negotiation, then releases the mic so macOS doesn't show the "in use" indicator
    // while idle. The engine is re-started on each start() call.
    func warmUp() async {
        // With no input device (e.g. a Mac Studio with no mic attached) installTap
        // raises an ObjC exception that Swift can't catch, so bail out first.
        guard refreshInputNodeIfNeeded() else { return }
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        _ = converter(for: nativeFormat)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { _, _ in }
        guard (try? engine.start()) != nil else {
            inputNode.removeTap(onBus: 0)
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func start() throws {
        samples = []
        guard refreshInputNodeIfNeeded() else { throw RecorderError.noInputDevice }
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = converter(for: nativeFormat) else {
            throw RecorderError.converterUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            self?.convert(buffer, using: converter)
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                throw error
            }
        }
        isRecording = true
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples
    }

    // An AVAudioEngine's input node stays bound to whatever device was the default
    // when it was created. If that was "no device" (hardware-side format of 0 Hz /
    // 0 ch; the output side still shows a placeholder 44.1k format), build a fresh
    // engine so a mic plugged in since then gets picked up. Returns whether a usable
    // input is available.
    @discardableResult
    private func refreshInputNodeIfNeeded() -> Bool {
        if Self.isUsable(engine.inputNode.inputFormat(forBus: 0)) { return true }
        guard !isRecording, !engine.isRunning else { return false }
        engine = AVAudioEngine()
        return Self.isUsable(engine.inputNode.inputFormat(forBus: 0))
    }

    // Rebuilds the converter when the input format changes (e.g. switching mics).
    private func converter(for nativeFormat: AVAudioFormat) -> AVAudioConverter? {
        if let converter, converter.inputFormat == nativeFormat { return converter }
        converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        return converter
    }

    private static func isUsable(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func convert(_ inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard outputFrames > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames)
        else { return }

        var consumed = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              let channelData = outputBuffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }
}
