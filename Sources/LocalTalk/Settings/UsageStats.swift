import Foundation

enum UsageStats {
    private static let secondsKey = "statsSeconds"
    private static let charsKey   = "statsChars"

    static var totalSeconds: Double { UserDefaults.standard.double(forKey: secondsKey) }
    static var totalChars: Int      { UserDefaults.standard.integer(forKey: charsKey) }

    static func addRecording(seconds: Double) {
        UserDefaults.standard.set(totalSeconds + seconds, forKey: secondsKey)
    }

    static func addCharacters(_ count: Int) {
        UserDefaults.standard.set(totalChars + count, forKey: charsKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: secondsKey)
        UserDefaults.standard.removeObject(forKey: charsKey)
    }

    static var formattedDuration: String {
        let t = Int(totalSeconds)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    static var formattedChars: String {
        let n = totalChars
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
