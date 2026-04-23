import AVFoundation

class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // Call once after mic permission is granted. Primes the converter and format
    // negotiation, then releases the mic so macOS doesn't show the "in use" indicator
    // while idle. The engine is re-started on each start() call.
    func warmUp() async {
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
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
        let inputNode = engine.inputNode
        if converter == nil {
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        }
        guard let converter else {
            throw NSError(domain: "MicrophoneRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            self?.convert(buffer, using: converter)
        }
        if !engine.isRunning { try engine.start() }
        isRecording = true
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples
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
