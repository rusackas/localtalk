import Foundation
import Testing
@testable import LocalTalk

/// Words laid out back to back, 0.4 s each, starting at `from`.
private func words(_ text: String, from: Float = 0) -> [WhisperTranscriber.Word] {
    text.split(separator: " ").enumerated().map { i, w in
        .init(text: String(w), start: from + Float(i) * 0.4, end: from + Float(i + 1) * 0.4)
    }
}

@Suite("Live mode transcript bookkeeping")
struct LiveTranscriptTests {
    @Test func firstPassTypesNothing() {
        var t = LiveTranscript()
        #expect(t.accept(words("hello there"), final: false, autoCapitalize: false).isEmpty)
        #expect(t.confirmedEnd == 0)
    }

    @Test func typesWhileStillTalkingWithinOneSegment() {
        // The regression: a single continuous sentence used to type nothing
        // until the key was released.
        var t = LiveTranscript()
        _ = t.accept(words("so I was"), final: false, autoCapitalize: true)
        let second = t.accept(words("so I was thinking we"), final: false, autoCapitalize: true)
        #expect(second == ["So", " I", " was"])
        let third = t.accept(words("so I was thinking we could"), final: false, autoCapitalize: true)
        #expect(third == [" thinking", " we"])
        #expect(t.typedText == "So I was thinking we")
    }

    @Test func wordsTheyDisagreeOnWaitForTheNextPass() {
        var t = LiveTranscript()
        _ = t.accept(words("meet at the bar."), final: false, autoCapitalize: false)
        // "bar." became "barn," and "the" was fine: only up to the disagreement is typed.
        #expect(t.accept(words("meet at the barn, then"), final: false, autoCapitalize: false)
                == ["meet", " at", " the"])
        #expect(t.accept(words("meet at the barn, then go"), final: false, autoCapitalize: false)
                == [" barn,", " then"])
    }

    @Test func contextAudioIsNeverRetyped() {
        var t = LiveTranscript()
        _ = t.accept(words("one two three"), final: false, autoCapitalize: false)
        _ = t.accept(words("one two three four"), final: false, autoCapitalize: false)
        #expect(t.typedText == "one two three")
        // Later passes re-feed earlier audio, with timestamps drifting slightly.
        let drifted = words("one two three four five").map {
            WhisperTranscriber.Word(text: $0.text, start: $0.start + 0.08, end: $0.end + 0.08)
        }
        // Only the newly agreed "four" is typed; "one two three" isn't repeated.
        #expect(t.accept(drifted, final: false, autoCapitalize: false) == [" four"])
        #expect(t.accept(words("one two three four five six"), final: false, autoCapitalize: false)
                == [" five"])
        #expect(t.typedText == "one two three four five")
    }

    @Test func finalPassTakesEverythingUntyped() {
        var t = LiveTranscript()
        _ = t.accept(words("all of"), final: false, autoCapitalize: true)
        _ = t.accept(words("all of this"), final: false, autoCapitalize: true)
        #expect(t.accept(words("all of this works"), final: true, autoCapitalize: true) == [" this", " works"])
        #expect(t.typedText == "All of this works")
    }

    @Test func finishingPunctuation() {
        var t = LiveTranscript()
        _ = t.accept(words("all done"), final: true, autoCapitalize: false)
        #expect(t.finishingPunctuation(addTrailingPeriod: false) == nil)
        #expect(t.finishingPunctuation(addTrailingPeriod: true) == ".")
        #expect(t.typedText == "all done.")
        #expect(t.finishingPunctuation(addTrailingPeriod: true) == nil)
    }

    @Test func noPeriodWhenNothingWasTyped() {
        var t = LiveTranscript()
        _ = t.accept([], final: true, autoCapitalize: false)
        #expect(t.finishingPunctuation(addTrailingPeriod: true) == nil)
    }

    @Test func liveAndBatchProduceTheSameTextForTheSameWords() {
        let text = "the quick brown fox jumps over the lazy dog"
        let all = words(text)
        var live = LiveTranscript()
        for n in 2...all.count { _ = live.accept(Array(all.prefix(n)), final: false, autoCapitalize: true) }
        _ = live.accept(all, final: true, autoCapitalize: true)
        _ = live.finishingPunctuation(addTrailingPeriod: true)
        #expect(live.typedText == OutputSettings.transform(text, autoCapitalize: true, addTrailingPeriod: true))
    }
}

@Suite("Whisper output cleanup")
struct WhisperCleanupTests {
    @Test func stripsSpecialTokens() {
        #expect(WhisperTranscriber.stripTokens("<|startoftranscript|><|en|> Hello<|endoftext|>") == " Hello")
        #expect(WhisperTranscriber.stripTokens("no tokens here") == "no tokens here")
        #expect(WhisperTranscriber.stripTokens("a < b | c > d") == "a < b | c > d")
    }

    @Test("Known silence hallucinations are filtered", arguments: [
        "Thank you", "thanks for watching", "♪", "[Music]", "(music)", "...",
        "you you you", "bye bye bye bye",
    ])
    func noise(text: String) {
        #expect(WhisperTranscriber.isNoise(text))
    }

    @Test("Real speech is kept", arguments: [
        "Thank you for the review", "hello", "bye bye", "Please subscribe me to the list",
    ])
    func notNoise(text: String) {
        #expect(!WhisperTranscriber.isNoise(text))
    }
}
