import Foundation

@main
struct QBittorrentAPICompatibilityTests {
    static func main() async throws {
        let baseURL = URL(string: CommandLine.arguments[1])!
        let secret = "test +&=%密碼"
        var passed = 0

        for scenario in ["legacy", "modern", "empty200", "custom-cookie"] {
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let url = baseURL.appendingPathComponent("\(scenario)/api/v2/auth/login")
            try await QBittorrentAPI.login(session: session, url: url, username: "tester", secret: secret, usesAPIKey: false)
            let versionURL = baseURL.appendingPathComponent("\(scenario)/api/v2/app/version")
            let version = try await QBittorrentAPI.version(session: session, url: versionURL)
            precondition(version == (scenario == "legacy" ? "v5.0.0" : "v5.2.3"))
            passed += 1
        }

        for scenario in ["wrong-password", "legacy-failure", "proxy-html", "missing-session", "banned", "wrong-path"] {
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            do {
                try await QBittorrentAPI.login(
                    session: session, url: baseURL.appendingPathComponent("\(scenario)/api/v2/auth/login"),
                    username: "tester", secret: secret, usesAPIKey: false
                )
                preconditionFailure("\(scenario) must fail")
            } catch is QBittorrentAPI.Failure {
                passed += 1
            }
        }

        for valid in [true, false] {
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            do {
                try await QBittorrentAPI.login(
                    session: session, url: baseURL.appendingPathComponent("bearer/api/v2/auth/login"),
                    username: "", secret: valid ? "qbt_test_key" : "invalid", usesAPIKey: true
                )
                precondition(valid, "An invalid API key must fail")
            } catch is QBittorrentAPI.Failure {
                precondition(!valid, "The valid API key must succeed without calling auth/login")
            }
            passed += 1
        }

        for status in [200, 202, 204] {
            try QBittorrentAPI.validate(HTTPURLResponse(url: baseURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
            passed += 1
        }
        do {
            try QBittorrentAPI.validate(HTTPURLResponse(url: baseURL, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            preconditionFailure("A missing action must be distinguishable for start/stop fallback")
        } catch QBittorrentAPI.Failure.notFound { passed += 1 }

        for (url, origin) in [
            ("https://example.com:443/qb/api/v2/torrents/info", "https://example.com"),
            ("http://example.com:80/api/v2/torrents/info", "http://example.com"),
            ("https://example.com:8443/api/v2/torrents/info", "https://example.com:8443")
        ] {
            var request = URLRequest(url: URL(string: url)!)
            QBittorrentAPI.configure(&request, apiKey: "qbt_test_key")
            precondition(request.value(forHTTPHeaderField: "Origin") == origin)
            precondition(request.value(forHTTPHeaderField: "Referer") == origin)
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer qbt_test_key")
            passed += 1
        }

        print("Passed \(passed) qBittorrent compatibility checks")
    }
}
