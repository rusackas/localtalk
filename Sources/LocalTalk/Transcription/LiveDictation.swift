import Foundation

/// The pure bookkeeping behind live mode: which words are settled enough to
/// type, and the exact text to type for each, given what's been typed already.
/// Kept free of audio/Whisper/typing so it can be unit-tested.
///
/// Uses "local agreement": a word is settled once two consecutive passes over
/// the same audio agree on it (same text, same position after the last typed
/// word). Whisper usually returns one segment for a whole continuous sentence,
/// so waiting for segment boundaries would mean nothing types until the key is
/// released; agreement on words keeps typing a word or two behind speech.
struct LiveTranscript {
    typealias Word = WhisperTranscriber.Word

    /// End time (s) of the last word that has been typed.
    private(set) var confirmedEnd: Float = 0
    /// Everything emitted so far, exactly as typed.
    private(set) var typedText = ""
    /// The previous pass's not-yet-typed words, to agree against.
    private var hypothesis: [Word] = []

    static let overlapTolerance: Float = 0.1

    /// Accepts the words from a transcription pass and returns the strings to
    /// type, in order. Interim passes type only words the previous pass agreed
    /// on; the final pass (key released) takes everything.
    mutating func accept(_ words: [Word], final: Bool, autoCapitalize: Bool) -> [String] {
        // Ignore words re-reported from audio that was already typed (passes
        // include earlier audio as context). Timestamps drift a little between
        // passes, so a word counts as new only if it's mostly after the typed
        // audio and doesn't start well inside it.
        let fresh = words.filter {
            ($0.start + $0.end) / 2 > confirmedEnd && $0.start >= confirmedEnd - Self.overlapTolerance
        }

        let settled: ArraySlice<Word>
        if final {
            settled = fresh[...]
            hypothesis = []
        } else {
            let agreed = zip(fresh, hypothesis).prefix { $0.text == $1.text }.count
            settled = fresh.prefix(agreed)
            hypothesis = Array(fresh.dropFirst(agreed))
        }

        var pieces: [String] = []
        for word in settled {
            confirmedEnd = max(confirmedEnd, word.end)
            let piece = typedText.isEmpty
                ? OutputSettings.capitalizingFirst(word.text, enabled: autoCapitalize)
                : " " + word.text
            typedText += piece
            pieces.append(piece)
        }
        return pieces
    }

    /// The closing punctuation to type once dictation ends, if any.
    mutating func finishingPunctuation(addTrailingPeriod: Bool) -> String? {
        guard OutputSettings.needsTrailingPeriod(typedText, enabled: addTrailingPeriod) else { return nil }
        typedText += "."
        return "."
    }
}

/// "Live" insertion mode: while the trigger key is held, repeatedly
/// re-transcribe the not-yet-typed tail of the recording and type each word
/// once two passes agree on it (see LiveTranscript). Whisper isn't a streaming
/// model, so this is the usual way to stream it. Nothing already typed is ever
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
    private var lastTranscribedCount = 0
    private var transcript = LiveTranscript()

    /// Only re-transcribe once at least this much new audio has arrived.
    private static let minNewSamples = 8_000  // 0.5 s at 16 kHz
    /// Seconds of already-typed audio to re-feed Whisper as context, so the
    /// untyped tail is heard mid-sentence rather than as a fresh utterance
    /// (which would capitalize its first word). Whisper pads every pass to a
    /// 30 s window anyway, so this costs little; repeated words are filtered.
    private static let contextSeconds: Float = 8

    private var passStart: Float { max(0, transcript.confirmedEnd - Self.contextSeconds) }

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

        if let words = try? await transcriber.transcribeWords(
            samples: finalSamples, from: passStart
        ) {
            await type(transcript.accept(words, final: true,
                                         autoCapitalize: OutputSettings.autoCapitalize))
        }
        if let period = transcript.finishingPunctuation(addTrailingPeriod: OutputSettings.addTrailingPeriod) {
            await injector.type(period)
        }
        return transcript.typedText
    }

    private func run() async {
        while !stopping {
            let snapshot = recorder.snapshot()
            guard snapshot.count - lastTranscribedCount >= Self.minNewSamples else {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            lastTranscribedCount = snapshot.count

            guard let words = try? await transcriber.transcribeWords(
                samples: snapshot, from: passStart
            ) else { continue }
            // Key released mid-pass: finish() redoes this tail with the full audio.
            if stopping { break }

            await type(transcript.accept(words, final: false,
                                         autoCapitalize: OutputSettings.autoCapitalize))
        }
    }

    private func type(_ pieces: [String]) async {
        for piece in pieces { await injector.type(piece) }
    }
}
