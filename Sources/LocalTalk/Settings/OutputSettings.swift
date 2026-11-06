import Foundation

enum InsertionMode: String, CaseIterable, Codable {
    case paste
    case type

    var displayName: String {
        switch self {
        case .paste: return "Paste"
        case .type:  return "Simulated typing"
        }
    }

    var explanation: String {
        switch self {
        case .paste:
            return "Inserts the transcript all at once via the clipboard (restored afterwards). Fast and works almost everywhere; may be blocked by password fields."
        case .type:
            return "Inserts the transcript as simulated keystrokes instead of pasting. Slower, but works in a few fields that block paste. Can garble if you type at the same time."
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
        var result = text
        if autoCapitalize, let first = result.first, first.isLetter {
            result = first.uppercased() + result.dropFirst()
        }
        if addTrailingPeriod {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = trimmed.last,
               !".!?,;:".contains(last) {
                result = trimmed + "."
            }
        }
        return result
    }
}
