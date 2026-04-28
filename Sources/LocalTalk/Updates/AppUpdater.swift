import Foundation
import Sparkle

final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static let releasesURL = URL(string: "https://github.com/rusackas/localtalk/releases")!

    var onUpdateFound: ((String) -> Void)?

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        DispatchQueue.main.async { [weak self] in
            self?.onUpdateFound?(version)
        }
    }
}
