import Foundation

enum DoubanNetworkRouting {
    nonisolated static let searchProxyUserDefaultsKey = "doubanSearchProxyURL"
    nonisolated static let imageProxyUserDefaultsKey = "doubanImageProxyURL"

    nonisolated static func searchRequestURL(query: String) -> URL? {
        if let proxyURL = configuredURL(forKey: searchProxyUserDefaultsKey) {
            return appendingQueryItem(name: "q", value: query, to: proxyURL)
        }

        guard let directURL = URL(string: "https://movie.douban.com/j/subject_suggest") else {
            return nil
        }
        return appendingQueryItem(name: "q", value: query, to: directURL)
    }

    nonisolated static func routedImageURL(for originalURL: URL) -> URL {
        guard needsDirectDoubanHeaders(for: originalURL) else { return originalURL }
        guard let proxyURL = configuredURL(forKey: imageProxyUserDefaultsKey) else { return originalURL }
        return appendingQueryItem(name: "imgurl", value: originalURL.absoluteString, to: proxyURL) ?? originalURL
    }

    nonisolated static func needsDirectDoubanHeaders(for url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("doubanio.com")
    }

    nonisolated private static func configuredURL(forKey key: String) -> URL? {
        guard
            let rawValue = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty,
            let url = URL(string: rawValue)
        else {
            return nil
        }
        return url
    }

    nonisolated private static func appendingQueryItem(name: String, value: String, to baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url
    }
}

enum DoubanSuggestionFetchResult: Sendable {
    case success([DoubanSuggestionItem])
    case negative
    case rateLimited(String)
    case timeout
    case decodeFailure
    case networkError(String)

    var failureReason: String? {
        switch self {
        case .success, .negative:
            return nil
        case .rateLimited(let reason):
            return reason
        case .timeout:
            return "timeout"
        case .decodeFailure:
            return "decode-failure"
        case .networkError(let reason):
            return reason
        }
    }
}

actor DoubanRequestClient {
    static let shared = DoubanRequestClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func fetchSuggestions(query: String) async -> DoubanSuggestionFetchResult {
        guard let url = DoubanNetworkRouting.searchRequestURL(query: query) else {
            return .networkError("bad-url")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        if url.host?.lowercased().contains("douban.com") == true {
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                    return .rateLimited("http-\(httpResponse.statusCode)")
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    return .networkError("http-\(httpResponse.statusCode)")
                }
            }

            if let rateLimitReason = Self.detectRateLimitReason(in: data) {
                return .rateLimited(rateLimitReason)
            }

            do {
                let decoded = try JSONDecoder()
                    .decode([DoubanSuggestionResponseItem].self, from: data)
                    .map { DoubanSuggestionItem(response: $0) }
                return decoded.isEmpty ? .negative : .success(decoded)
            } catch {
                return .decodeFailure
            }
        } catch let error as URLError {
            if error.code == .timedOut {
                return .timeout
            }
            return .networkError(error.localizedDescription)
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    private static func detectRateLimitReason(in data: Data) -> String? {
        guard let body = String(data: data, encoding: .utf8)?.lowercased(), !body.isEmpty else {
            return nil
        }

        let markers = [
            "subject_ip_rate_limit",
            "rate limit",
            "sec.douban.com",
            "访问受限",
            "请求过于频繁"
        ]
        return markers.first(where: { body.contains($0) })
    }
}
