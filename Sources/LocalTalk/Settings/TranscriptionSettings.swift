import Foundation

enum ModelSize: String, CaseIterable, Codable {
    case tiny
    case base
    case small
    case medium

    var displayName: String {
        switch self {
        case .tiny:   return "Tiny (fastest, ~40 MB)"
        case .base:   return "Base (~75 MB)"
        case .small:  return "Small (~250 MB)"
        case .medium: return "Medium (most accurate, ~800 MB)"
        }
    }
}

enum Language: String, CaseIterable, Codable {
    case auto, en, es, fr, de, it, pt, nl, ja, zh, ko, ru, ar, hi

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .en:   return "English"
        case .es:   return "Spanish"
        case .fr:   return "French"
        case .de:   return "German"
        case .it:   return "Italian"
        case .pt:   return "Portuguese"
        case .nl:   return "Dutch"
        case .ja:   return "Japanese"
        case .zh:   return "Chinese"
        case .ko:   return "Korean"
        case .ru:   return "Russian"
        case .ar:   return "Arabic"
        case .hi:   return "Hindi"
        }
    }

    // Code passed to WhisperKit DecodingOptions for multilingual models.
    // Auto returns nil so Whisper runs its own language detection.
    var whisperCode: String? {
        self == .auto ? nil : rawValue
    }
}

enum TranscriptionSettings {
    private static let sizeKey = "modelSize"
    private static let languageKey = "language"

    static var modelSize: ModelSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: sizeKey),
                  let size = ModelSize(rawValue: raw) else { return .small }
            return size
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey) }
    }

    static var language: Language {
        get {
            guard let raw = UserDefaults.standard.string(forKey: languageKey),
                  let lang = Language(rawValue: raw) else { return .en }
            return lang
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: languageKey) }
    }

    // English-only variants are faster and more accurate for English. Any other
    // language (including auto-detect) uses the multilingual variant.
    static var modelName: String {
        language == .en ? "\(modelSize.rawValue).en" : modelSize.rawValue
    }
}
