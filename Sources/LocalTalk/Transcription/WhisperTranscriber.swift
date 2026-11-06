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

    struct Word: Equatable {
        /// Trimmed word text, including any attached punctuation ("there,").
        let text: String
        /// Start/end in seconds from the start of the recording.
        let start: Float
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
        try await run(samples: samples, from: start, wordTimestamps: false).map { segment in
            let text = Self.clean(segment.text)
            return Segment(text: Self.isNoise(text) ? "" : text, end: segment.end)
        }
    }

    /// Word-level transcription of the audio after `start` seconds, for live mode.
    /// Words from segments that are blank or known hallucinations are dropped.
    func transcribeWords(samples: [Float], from start: Float = 0) async throws -> [Word] {
        try await run(samples: samples, from: start, wordTimestamps: true).flatMap { segment -> [Word] in
            let text = Self.clean(segment.text)
            guard !text.isEmpty, !Self.isNoise(text) else { return [] }
            return (segment.words ?? []).compactMap { w in
                let word = Self.clean(w.word)
                return word.isEmpty ? nil : Word(text: word, start: w.start, end: w.end)
            }
        }
    }

    private func run(samples: [Float], from start: Float, wordTimestamps: Bool) async throws -> [TranscriptionSegment] {
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
        options.wordTimestamps = wordTimestamps
        if start > 0 { options.clipTimestamps = [start] }

        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments)
    }

    private static func clean(_ text: String) -> String {
        stripTokens(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|>]+\|>"#, with: "", options: .regularExpression)
    }

    static func isNoise(_ text: String) -> Bool {
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
