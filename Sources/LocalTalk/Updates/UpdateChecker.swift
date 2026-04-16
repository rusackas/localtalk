import Foundation

struct UpdateChecker {
    static let currentVersion = "1.0.0"

    private static let apiURL = URL(string: "https://api.github.com/repos/rusackas/localtalk/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/rusackas/localtalk/releases")!

    // Returns the latest version tag if it's newer than currentVersion, else nil.
    static func availableUpdate() async -> String? {
        do {
            var req = URLRequest(url: apiURL)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            return isNewer(latest, than: currentVersion) ? latest : nil
        } catch {
            return nil
        }
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for (x, y) in zip(av, bv) {
            if x > y { return true }
            if x < y { return false }
        }
        return av.count > bv.count
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}
