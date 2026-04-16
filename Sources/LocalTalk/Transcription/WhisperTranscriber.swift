import Foundation
import WhisperKit

class WhisperTranscriber {
    private var whisper: WhisperKit?
    private(set) var isReady = false

    func load(model: String = "small.en") async throws {
        let config = WhisperKitConfig(model: model)
        whisper = try await WhisperKit(config)
        isReady = true
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let whisper else { throw TranscriberError.notLoaded }
        guard samples.count > 1600 else { return "" }  // < 0.1s of audio

        let options = DecodingOptions(
            task: .transcribe,
            temperature: 0.0,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )

        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)

        return results
            .flatMap(\.segments)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoise($0) }
            .joined(separator: " ")
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
