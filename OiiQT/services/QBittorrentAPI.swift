import Foundation

nonisolated enum QBittorrentAPI {
    static func configure(_ request: inout URLRequest, apiKey: String? = nil) {
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if var origin = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
            origin.path = ""
            origin.query = nil
            origin.fragment = nil
            if (origin.scheme == "https" && origin.port == 443) || (origin.scheme == "http" && origin.port == 80) {
                origin.port = nil
            }
            request.setValue(origin.string, forHTTPHeaderField: "Origin")
            request.setValue(origin.string, forHTTPHeaderField: "Referer")
        }
        request.setValue(apiKey.map { "Bearer \($0)" }, forHTTPHeaderField: "Authorization")
    }

    static func login(session: URLSession, url: URL, username: String, secret: String, usesAPIKey: Bool) async throws {
        let versionURL = url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("app/version")
        if usesAPIKey {
            _ = try await version(session: session, url: versionURL, apiKey: secret)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configure(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["username": username, "password": secret])
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if body == "Fails." { throw Failure.unauthorized }
        if body == "Ok." { return }

        // 5.2 returns 204 with a QBT_SID_* cookie. Verify the session instead of
        // depending on a cookie name or mistaking a proxy's HTML page for success.
        guard body.isEmpty else { throw Failure.unexpectedResponse }
        _ = try await version(session: session, url: versionURL)
    }

    static func version(session: URLSession, url: URL, apiKey: String? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        configure(&request, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: #"^v?\d+\.\d+(?:\.\d+)?(?:[A-Za-z0-9.+_-]*)$"#, options: .regularExpression) != nil else {
            throw Failure.unexpectedResponse
        }
        return version
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Failure.unexpectedResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        case 404: throw Failure.notFound
        default: throw Failure.http(http.statusCode)
        }
    }

    static func formBody(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }

    enum Failure: LocalizedError {
        case unauthorized, forbidden, notFound, unexpectedResponse, http(Int)

        var messageKey: String {
            switch self {
            case .unauthorized:
                return "qBittorrent rejected authentication (HTTP 401). Check your credentials and authentication mode, or the reverse proxy's Host/Origin settings."
            case .forbidden:
                return "qBittorrent denied access (HTTP 403). Check the session/API key and whether your IP was banned after failed logins."
            case .notFound:
                return "qBittorrent API not found (HTTP 404). Check the API path and reverse proxy configuration."
            case .unexpectedResponse:
                return "Unexpected qBittorrent response. Check that the address points to the Web API rather than a proxy login page."
            case .http:
                return "qBittorrent request failed (HTTP %d)."
            }
        }

        var errorDescription: String? {
            let message = NSLocalizedString(messageKey, comment: "")
            if case .http(let status) = self { return String(format: message, status) }
            return message
        }
    }
}
