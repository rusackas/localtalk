import CoreGraphics
import Foundation

enum TriggerMode: String, Codable {
    case flagsChanged  // modifier-only keys: fn, right-option, right-control
    case keyCombo      // regular key + optional modifiers
}

struct TriggerKey: Codable, Equatable {
    var keyCode: UInt16
    var flagsValue: UInt64  // CGEventFlags.RawValue
    var mode: TriggerMode
    var displayName: String

    static let fn = TriggerKey(keyCode: 63, flagsValue: CGEventFlags.maskSecondaryFn.rawValue,
                                mode: .flagsChanged, displayName: "fn / Globe")
    static let rightOption = TriggerKey(keyCode: 61, flagsValue: CGEventFlags.maskAlternate.rawValue,
                                         mode: .flagsChanged, displayName: "Right Option (⌥)")
    static let rightControl = TriggerKey(keyCode: 62, flagsValue: CGEventFlags.maskControl.rawValue,
                                          mode: .flagsChanged, displayName: "Right Control (⌃)")

    static let presets: [TriggerKey] = [.fn, .rightOption, .rightControl]

    static func load() -> TriggerKey {
        guard let data = UserDefaults.standard.data(forKey: "triggerKey"),
              let key = try? JSONDecoder().decode(TriggerKey.self, from: data) else {
            return .fn
        }
        return key
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "triggerKey")
    }
}
