import AppKit

enum FeedbackSound: String, CaseIterable, Codable {
    case off
    case tink
    case pop
    case glass
    case blow
    case bottle

    var displayName: String {
        switch self {
        case .off:    return "Off"
        case .tink:   return "Tink"
        case .pop:    return "Pop"
        case .glass:  return "Glass"
        case .blow:   return "Blow"
        case .bottle: return "Bottle"
        }
    }

    // macOS ships system sounds under /System/Library/Sounds with these names.
    var systemSoundName: String? {
        switch self {
        case .off:    return nil
        case .tink:   return "Tink"
        case .pop:    return "Pop"
        case .glass:  return "Glass"
        case .blow:   return "Blow"
        case .bottle: return "Bottle"
        }
    }
}

enum AudioFeedback {
    private static let key = "feedbackSound"

    static var selected: FeedbackSound {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let sound = FeedbackSound(rawValue: raw) else { return .off }
            return sound
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    // Played on both start and stop. NSSound caches named sounds, so repeated
    // plays are cheap. play() is non-blocking.
    static func play() {
        guard let name = selected.systemSoundName,
              let sound = NSSound(named: name) else { return }
        sound.stop()  // allow rapid re-trigger without overlap
        sound.play()
    }

    static func preview(_ sound: FeedbackSound) {
        guard let name = sound.systemSoundName,
              let ns = NSSound(named: name) else { return }
        ns.stop()
        ns.play()
    }
}
