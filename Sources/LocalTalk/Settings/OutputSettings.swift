import Foundation

enum InsertionMode: String, CaseIterable, Codable {
    case paste
    case type
    case live

    var displayName: String {
        switch self {
        case .paste: return "Paste"
        case .type:  return "Simulated typing"
        case .live:  return "Live (types as you speak)"
        }
    }

    var explanation: String {
        switch self {
        case .paste:
            return "Inserts the transcript all at once via the clipboard (restored afterwards). Fast and works almost everywhere; may be blocked by password fields."
        case .type:
            return "Inserts the transcript as simulated keystrokes instead of pasting. Slower, but works in a few fields that block paste. Can garble if you type at the same time."
        case .live:
            return "Types each phrase as soon as Whisper is confident in it, while you're still holding the key; the rest lands when you let go. Text arrives roughly a phrase behind your voice. Uses more CPU, so it works best with the Tiny or Base model."
        }
    }
}

enum OutputSettings {
    private static let modeKey = "insertionMode"
    private static let autoCapKey = "autoCapitalize"
    private static let trailingPeriodKey = "addTrailingPeriod"

    static var insertionMode: InsertionMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let mode = InsertionMode(rawValue: raw) else { return .paste }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var autoCapitalize: Bool {
        get { UserDefaults.standard.bool(forKey: autoCapKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoCapKey) }
    }

    static var addTrailingPeriod: Bool {
        get { UserDefaults.standard.bool(forKey: trailingPeriodKey) }
        set { UserDefaults.standard.set(newValue, forKey: trailingPeriodKey) }
    }

    static func transform(_ text: String) -> String {
        var result = capitalizingFirst(text)
        if addTrailingPeriod {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if needsTrailingPeriod(trimmed) { result = trimmed + "." }
        }
        return result
    }

    // Split out so live mode can apply them to the first and last phrase only.
    static func capitalizingFirst(_ text: String) -> String {
        guard autoCapitalize, let first = text.first, first.isLetter else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func needsTrailingPeriod(_ text: String) -> Bool {
        guard addTrailingPeriod, let last = text.last(where: { !$0.isWhitespace }) else { return false }
        return !".!?,;:".contains(last)
    }
}
