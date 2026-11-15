import CoreAudio
import Foundation

enum InputDeviceSettings {
    private static let uidKey = "inputDeviceUID"
    private static let nameKey = "inputDeviceName"

    /// UID of the chosen microphone; nil follows the system default input.
    static var selectedUID: String? {
        UserDefaults.standard.string(forKey: uidKey)
    }

    /// The name is saved alongside the UID so the menu can still label the
    /// choice while the device is unplugged.
    static func select(uid: String?, name: String?) {
        if let uid {
            UserDefaults.standard.set(uid, forKey: uidKey)
            UserDefaults.standard.set(name, forKey: nameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: uidKey)
            UserDefaults.standard.removeObject(forKey: nameKey)
        }
    }

    /// The chosen device if it is connected right now. nil means "use the
    /// system default", either by choice or because the chosen one is unplugged.
    static func selectedDeviceID() -> AudioDeviceID? {
        guard let uid = selectedUID else { return nil }
        return AudioInputDevice.all().first { $0.uid == uid }?.id
    }

    struct Choice: Equatable {
        let title: String
        /// nil for the system default.
        let uid: String?
        /// The device's own name, without any "(not connected)" suffix.
        let name: String?
    }

    static func choices() -> [Choice] {
        choices(devices: AudioInputDevice.all(), savedUID: selectedUID,
                savedName: UserDefaults.standard.string(forKey: nameKey))
    }

    /// Menu entries: system default first, then connected devices, then the
    /// saved device if it isn't connected (so opening Settings and pressing
    /// Save doesn't silently forget it).
    static func choices(devices: [AudioInputDevice], savedUID: String?, savedName: String?) -> [Choice] {
        var result = [Choice(title: "System default", uid: nil, name: nil)]
        result += devices.map { Choice(title: $0.name, uid: $0.uid, name: $0.name) }
        if let savedUID, !devices.contains(where: { $0.uid == savedUID }) {
            let name = savedName ?? "Unknown microphone"
            result.append(Choice(title: "\(name) (not connected)", uid: savedUID, name: name))
        }
        return result
    }
}
