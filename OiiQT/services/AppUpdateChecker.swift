import Foundation
import Observation

struct AppRelease {
    let version: String
    let downloadURL: URL

    func installURL(scheme: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "install"
        components.queryItems = [URLQueryItem(name: "url", value: downloadURL.absoluteString)]
        return components.url!
    }
}

@Observable
final class AppUpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/gangz1o/OiiQT/releases/latest")!

    private(set) var release: AppRelease?
    private(set) var isChecking = false
    private(set) var hasChecked = false
    private(set) var checkFailed = false

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        checkFailed = false
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            release = try Self.availableRelease(
                in: data,
                installedVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            )
            hasChecked = true
        } catch {
            if !Task.isCancelled { checkFailed = true }
        }
    }

    static func availableRelease(in data: Data, installedVersion: String) throws -> AppRelease? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard version.wholeMatch(of: #/[0-9]+(?:\.[0-9]+)*/#) != nil else {
            throw URLError(.cannotParseResponse)
        }

        guard compareVersions(version, installedVersion) == .orderedDescending,
              let ipa = release.assets.first(where: { $0.name == "OiiQT-unsigned.ipa" && $0.state == "uploaded" })
        else { return nil }

        return AppRelease(version: version, downloadURL: ipa.downloadURL)
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let trailingZeroes = #"(\.0)+$"#
        return lhs.replacingOccurrences(of: trailingZeroes, with: "", options: .regularExpression)
            .compare(rhs.replacingOccurrences(of: trailingZeroes, with: "", options: .regularExpression), options: .numeric)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let state: String
            let downloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, state
                case downloadURL = "browser_download_url"
            }
        }
    }
}
