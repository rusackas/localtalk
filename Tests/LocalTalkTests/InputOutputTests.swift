import AVFoundation
import CoreGraphics
import Testing
@testable import LocalTalk

@Suite("Keystroke chunking")
struct KeystrokeChunkTests {
    @Test func asciiIsOneUnitPerKeystroke() {
        let chunks = TextInjector.keystrokeChunks("hi!")
        #expect(chunks == [[0x68], [0x69], [0x21]])
    }

    @Test func surrogatePairsStayTogether() {
        let chunks = TextInjector.keystrokeChunks("a😀b")
        #expect(chunks.count == 3)
        #expect(chunks[1].count == 2)
        #expect(String(utf16CodeUnits: chunks[1], count: 2) == "😀")
    }

    @Test("Chunks always reassemble to the original text", arguments: [
        "", "plain", "café", "日本語", "👍🏽 thumbs", "e\u{301}", "🇺🇸 flag", "mixed 😀 text 🎉!",
    ])
    func roundTrip(text: String) {
        let units = TextInjector.keystrokeChunks(text).flatMap { $0 }
        #expect(String(decoding: units, as: UTF16.self) == text)
    }
}

@Suite("Audio capture")
struct AudioCaptureTests {
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                       channels: 1, interleaved: false)!

    private func sineBuffer(rate: Double, channels: AVAudioChannelCount, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<Int(channels) {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) {
                data[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / Float(rate))
            }
        }
        return buffer
    }

    @Test("Resamples common device formats to 16 kHz mono", arguments: [
        (48_000.0, AVAudioChannelCount(1)), (44_100.0, 1), (48_000.0, 2), (16_000.0, 1), (96_000.0, 2),
    ])
    func resample(rate: Double, channels: AVAudioChannelCount) throws {
        // Feed audio the way the input tap does: a stream of ~0.1 s buffers
        // through one long-lived converter.
        let first = sineBuffer(rate: rate, channels: channels, seconds: 0.1)
        let converter = try #require(AVAudioConverter(from: first.format, to: target))
        var output: [Float] = []
        for _ in 0..<20 {
            let buffer = sineBuffer(rate: rate, channels: channels, seconds: 0.1)
            output += MicrophoneRecorder.resample(buffer, using: converter, to: target)
        }

        // 2 s at 16 kHz = 32,000 samples. The converter holds back a few ms of
        // latency on the first buffer only, so allow ~1%.
        #expect(output.count > 31_600 && output.count <= 32_000)
        let peak = output.map(abs).max() ?? 0
        #expect(peak > 0.2 && peak < 1.0)
    }

    @Test func usableFormatRequiresRateAndChannels() {
        #expect(MicrophoneRecorder.isUsable(target))
        #expect(MicrophoneRecorder.isUsable(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!))
    }
}

@Suite("Trigger key monitor")
struct KeyMonitorTests {
    private final class Recorder {
        var downs = 0
        var ups = 0
    }

    private func flagsEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    private func makeMonitor(_ trigger: TriggerKey, _ rec: Recorder) -> KeyMonitor {
        KeyMonitor(trigger: trigger, onDown: { rec.downs += 1 }, onUp: { rec.ups += 1 })
    }

    @Test("Press and release fire once each and are swallowed", arguments: TriggerKey.presets)
    func pressAndRelease(trigger: TriggerKey) {
        let rec = Recorder()
        let monitor = makeMonitor(trigger, rec)
        let keyCode = CGKeyCode(trigger.keyCode)
        let down = flagsEvent(keyCode: keyCode, flags: CGEventFlags(rawValue: trigger.flagsValue))
        let up = flagsEvent(keyCode: keyCode, flags: [])

        #expect(monitor.handle(event: down, type: .flagsChanged) == nil)
        #expect(rec.downs == 1 && rec.ups == 0)
        #expect(monitor.handle(event: up, type: .flagsChanged) == nil)
        #expect(rec.downs == 1 && rec.ups == 1)
    }

    @Test func repeatedDownWithoutUpDoesNotRestart() {
        let rec = Recorder()
        let monitor = makeMonitor(.fn, rec)
        let down = flagsEvent(keyCode: 63, flags: .maskSecondaryFn)
        _ = monitor.handle(event: down, type: .flagsChanged)
        _ = monitor.handle(event: down, type: .flagsChanged)
        #expect(rec.downs == 1)
    }

    @Test func releaseWithoutPressIsIgnored() {
        let rec = Recorder()
        let monitor = makeMonitor(.fn, rec)
        _ = monitor.handle(event: flagsEvent(keyCode: 63, flags: []), type: .flagsChanged)
        #expect(rec.ups == 0)
    }

    @Test func otherKeysPassThroughUntouched() {
        let rec = Recorder()
        let monitor = makeMonitor(.rightOption, rec)
        // Left Option (58) sets the same flag but isn't the trigger.
        let leftOption = flagsEvent(keyCode: 58, flags: .maskAlternate)
        #expect(monitor.handle(event: leftOption, type: .flagsChanged) != nil)
        let typing = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        #expect(monitor.handle(event: typing, type: .keyDown) != nil)
        #expect(rec.downs == 0 && rec.ups == 0)
    }

    @Test func changingTriggerMidPressResetsState() {
        let rec = Recorder()
        let monitor = makeMonitor(.fn, rec)
        _ = monitor.handle(event: flagsEvent(keyCode: 63, flags: .maskSecondaryFn), type: .flagsChanged)
        monitor.updateTrigger(.rightControl)
        // The old key's release no longer matters; the new key works from scratch.
        _ = monitor.handle(event: flagsEvent(keyCode: 63, flags: []), type: .flagsChanged)
        #expect(rec.ups == 0)
        _ = monitor.handle(event: flagsEvent(keyCode: 62, flags: .maskControl), type: .flagsChanged)
        #expect(rec.downs == 2)
    }
}
