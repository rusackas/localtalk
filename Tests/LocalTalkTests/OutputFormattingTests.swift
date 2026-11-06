import CoreGraphics
import Foundation
import Testing
@testable import LocalTalk

@Suite("Output formatting")
struct OutputFormattingTests {
    @Test("Capitalizes only when enabled and the first character is a letter", arguments: [
        ("hello world", true, "Hello world"),
        ("hello world", false, "hello world"),
        ("Hello", true, "Hello"),
        ("42 apples", true, "42 apples"),
        ("élan", true, "Élan"),
        ("", true, ""),
    ])
    func capitalizingFirst(input: String, enabled: Bool, expected: String) {
        #expect(OutputSettings.capitalizingFirst(input, enabled: enabled) == expected)
    }

    @Test("Trailing period is only needed when enabled and text lacks closing punctuation", arguments: [
        ("hello", true, true),
        ("hello", false, false),
        ("hello.", true, false),
        ("really?", true, false),
        ("wow!", true, false),
        ("list:", true, false),
        ("hello.  ", true, false),   // trailing whitespace ignored
        ("hello  ", true, true),
        ("", true, false),
        ("   ", true, false),
    ])
    func needsTrailingPeriod(input: String, enabled: Bool, expected: Bool) {
        #expect(OutputSettings.needsTrailingPeriod(input, enabled: enabled) == expected)
    }

    @Test func transformAppliesBothRules() {
        #expect(OutputSettings.transform("send it", autoCapitalize: true, addTrailingPeriod: true) == "Send it.")
        #expect(OutputSettings.transform("send it  ", autoCapitalize: false, addTrailingPeriod: true) == "send it.")
        #expect(OutputSettings.transform("Done!", autoCapitalize: true, addTrailingPeriod: true) == "Done!")
        #expect(OutputSettings.transform("as is ", autoCapitalize: false, addTrailingPeriod: false) == "as is ")
    }
}

@Suite("Persisted settings values")
struct PersistedSettingsTests {
    // These raw values are stored in UserDefaults; renaming a case would
    // silently reset users' settings on upgrade.
    @Test func insertionModeRawValuesAreStable() {
        #expect(InsertionMode(rawValue: "paste") == .paste)
        #expect(InsertionMode(rawValue: "type") == .type)
        #expect(InsertionMode(rawValue: "live") == .live)
        #expect(InsertionMode.allCases == [.paste, .type, .live])
    }

    @Test func modelSizeAndLanguageRawValuesAreStable() {
        #expect(ModelSize.allCases.map(\.rawValue) == ["tiny", "base", "small", "medium"])
        #expect(Language(rawValue: "auto") == .auto)
        #expect(Language(rawValue: "en") == .en)
        #expect(Language.allCases.count == 14)
    }

    @Test("English uses the .en model variant; other languages use multilingual", arguments: ModelSize.allCases)
    func modelName(size: ModelSize) {
        #expect(TranscriptionSettings.modelName(size: size, language: .en) == "\(size.rawValue).en")
        #expect(TranscriptionSettings.modelName(size: size, language: .auto) == size.rawValue)
        #expect(TranscriptionSettings.modelName(size: size, language: .ja) == size.rawValue)
    }

    @Test func languageWhisperCodes() {
        #expect(Language.auto.whisperCode == nil)
        for language in Language.allCases where language != .auto {
            #expect(language.whisperCode == language.rawValue)
        }
    }

    @Test("Trigger keys round-trip through their stored JSON", arguments: TriggerKey.presets)
    func triggerKeyRoundTrip(key: TriggerKey) throws {
        let data = try JSONEncoder().encode(key)
        #expect(try JSONDecoder().decode(TriggerKey.self, from: data) == key)
    }

    @Test func triggerPresetsAreModifierOnly() {
        #expect(TriggerKey.presets.allSatisfy { $0.mode == .flagsChanged })
        #expect(Set(TriggerKey.presets.map(\.keyCode)).count == TriggerKey.presets.count)
    }
}

@Suite("Usage stats formatting")
struct UsageStatsFormattingTests {
    @Test(arguments: [
        (0.0, "0s"), (59.9, "59s"), (60, "1m 0s"), (125, "2m 5s"),
        (3600, "1h 0m 0s"), (3725, "1h 2m 5s"),
    ])
    func duration(seconds: Double, expected: String) {
        #expect(UsageStats.formatDuration(seconds) == expected)
    }

    @Test(arguments: [
        (0, "0"), (999, "999"), (1_000, "1.0K"), (12_345, "12.3K"),
        (1_000_000, "1.0M"), (2_550_000, "2.5M"),
    ])
    func count(n: Int, expected: String) {
        #expect(UsageStats.formatCount(n) == expected)
    }
}

@Suite("Shift for live mode")
@MainActor
struct ShiftLiveTests {
    @Test(arguments: TriggerKey.presets)
    func shiftMakesOneDictationLive(trigger: TriggerKey) {
        #expect(AppDelegate.wantsLive(mode: .paste, shiftHeld: true, trigger: trigger))
        #expect(AppDelegate.wantsLive(mode: .type, shiftHeld: true, trigger: trigger))
        #expect(!AppDelegate.wantsLive(mode: .paste, shiftHeld: false, trigger: trigger))
        #expect(AppDelegate.wantsLive(mode: .live, shiftHeld: false, trigger: trigger))
    }

    @Test func shiftComboTriggerDoesNotForceLive() {
        let combo = TriggerKey(keyCode: 49, flagsValue: CGEventFlags.maskShift.rawValue,
                               mode: .keyCombo, displayName: "⇧Space")
        #expect(!AppDelegate.wantsLive(mode: .paste, shiftHeld: true, trigger: combo))
    }
}
