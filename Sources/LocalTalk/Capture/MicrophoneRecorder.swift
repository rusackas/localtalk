import AVFoundation

class MicrophoneRecorder {
    private var audioRecorder: AVAudioRecorder?
    private let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("localtalk_rec.wav")
    private(set) var isRecording = false

    // Records microphone at 16 kHz mono — the format WhisperKit expects.
    func start() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }

    // Stops recording and returns Float32 samples at 16 kHz.
    func stop() -> [Float] {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        return loadSamples()
    }

    private func loadSamples() -> [Float] {
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard FileManager.default.fileExists(atPath: tempURL.path) else { return [] }
        do {
            let file = try AVAudioFile(forReading: tempURL)
            let capacity = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return [] }
            try file.read(into: buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        } catch {
            return []
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: tempURL)
    }
}
