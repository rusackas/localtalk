import Foundation

/// "Live" insertion mode: while the trigger key is held, repeatedly
/// re-transcribe the not-yet-confirmed tail of the recording and type each
/// phrase once Whisper has moved past it.
///
/// Whisper isn't a streaming model, so this follows the same approach as
/// WhisperKit's AudioStreamTranscriber: every pass transcribes the audio after
/// the last confirmed point, and every segment except the trailing one is
/// treated as settled (Whisper only starts a new segment once it's done with the
/// previous one). The trailing segment may still change, so it isn't typed until
/// a later pass confirms it or the key is released. Nothing already typed is ever
/// revised, which keeps this safe in any app.
///
/// We drive our own MicrophoneRecorder rather than AudioStreamTranscriber so the
/// no-mic / permission handling and the single audio engine stay in one place.
@MainActor
final class LiveDictation {
    private let recorder: MicrophoneRecorder
    private let transcriber: WhisperTranscriber
    private let injector: TextInjector

    private var loop: Task<Void, Never>?
    private var stopping = false
    private var lastConfirmedEnd: Float = 0
    private var lastTranscribedCount = 0
    private(set) var typedText = ""

    /// Only re-transcribe once at least this much new audio has arrived.
    private static let minNewSamples = 16_000  // 1 s at 16 kHz
    /// Trailing segments held back as still-provisional on each pass.
    private static let unconfirmedTail = 1

    init(recorder: MicrophoneRecorder, transcriber: WhisperTranscriber, injector: TextInjector) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.injector = injector
    }

    /// Starts the live loop once `previous` (an earlier queued transcription)
    /// has finished, so text from separate dictations never interleaves.
    func start(after previous: Task<Void, Never>?) {
        loop = Task { @MainActor in
            await previous?.value
            await run()
        }
    }

    /// Call after the key is released with the complete recording. Types
    /// whatever hadn't been confirmed yet and returns everything typed.
    func finish(finalSamples: [Float]) async -> String {
        stopping = true
        await loop?.value

        if let segments = try? await transcriber.transcribeSegments(samples: finalSamples, from: lastConfirmedEnd) {
            for segment in segments where segment.end > lastConfirmedEnd {
                await emit(segment.text)
                lastConfirmedEnd = segment.end
            }
        }
        if OutputSettings.needsTrailingPeriod(typedText) {
            await injector.type(".")
            typedText += "."
        }
        return typedText
    }

    private func run() async {
        while !stopping {
            let snapshot = recorder.snapshot()
            guard snapshot.count - lastTranscribedCount >= Self.minNewSamples else {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            lastTranscribedCount = snapshot.count

            guard let segments = try? await transcriber.transcribeSegments(
                samples: snapshot, from: lastConfirmedEnd
            ) else { continue }
            // Key released mid-pass: finish() redoes this tail with the full audio.
            if stopping { break }

            guard segments.count > Self.unconfirmedTail else { continue }
            for segment in segments.dropLast(Self.unconfirmedTail) where segment.end > lastConfirmedEnd {
                await emit(segment.text)
                lastConfirmedEnd = segment.end
            }
        }
    }

    private func emit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let piece = typedText.isEmpty ? OutputSettings.capitalizingFirst(trimmed) : " " + trimmed
        await injector.type(piece)
        typedText += piece
    }
}
