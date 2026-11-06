import Foundation
import WhisperKit

class WhisperTranscriber {
    private var whisper: WhisperKit?
    private(set) var isReady = false

    func load(model: String = TranscriptionSettings.modelName) async throws {
        // load: true is required. Without a modelFolder, WhisperKit's init only
        // downloads the model and defers loading (CoreML compile + ANE
        // specialization, which can take a while) to the first transcribe() call,
        // which left the first dictation stuck in "processing".
        let config = WhisperKitConfig(model: model, load: true)
        // Not ready while (re)loading, so the trigger key is ignored and the
        // status icon stays on the loading spinner. If a reload fails, keep
        // using the previously loaded model.
        isReady = false
        defer { isReady = whisper != nil }
        whisper = try await WhisperKit(config)
    }

    struct Segment {
        /// Cleaned text; empty if the segment was blank or a known hallucination.
        let text: String
        /// End time in seconds from the start of the recording.
        let end: Float
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await transcribeSegments(samples: samples)
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Transcribes `samples`, skipping everything before `start` seconds. Used by
    /// live mode to re-transcribe only the not-yet-confirmed tail of a recording.
    func transcribeSegments(samples: [Float], from start: Float = 0) async throws -> [Segment] {
        guard let whisper else { throw TranscriberError.notLoaded }
        let startSample = Int(start * Float(WhisperKit.sampleRate))
        guard samples.count - startSample > 1600 else { return [] }  // < 0.1s of audio

        var options = DecodingOptions(
            task: .transcribe,
            language: TranscriptionSettings.language.whisperCode,
            temperature: 0.0,
            skipSpecialTokens: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )
        if start > 0 { options.clipTimestamps = [start] }

        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)

        return results.flatMap(\.segments).map { segment in
            let text = stripTokens(segment.text).trimmingCharacters(in: .whitespacesAndNewlines)
            return Segment(text: isNoise(text) ? "" : text, end: segment.end)
        }
    }

    private func stripTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|>]+\|>"#, with: "", options: .regularExpression)
    }

    private func isNoise(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let noisePatterns = ["thank you", "thanks for watching", "subscribe", "♪", "[music]", "(music)", "..."]
        if noisePatterns.contains(lowered) { return true }
        let words = lowered.split(separator: " ")
        return words.count >= 3 && Set(words).count == 1
    }
}

enum TranscriberError: Error {
    case notLoaded
}
