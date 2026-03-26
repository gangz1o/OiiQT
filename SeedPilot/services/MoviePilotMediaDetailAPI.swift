import Foundation

actor MoviePilotMediaDetailAPIClient {
    static let shared = MoviePilotMediaDetailAPIClient()

    private enum AuthenticationMode: CaseIterable {
        case bearerHeader
        case apiKeyHeader
        case queryAPIKey
        case queryToken
    }

    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    private struct Route {
        let path: String
        let queryItems: [URLQueryItem]
        let method: HTTPMethod
        let bodyData: Data?

        init(
            path: String,
            queryItems: [URLQueryItem] = [],
            method: HTTPMethod = .get,
            bodyData: Data? = nil
        ) {
            self.path = path
            self.queryItems = queryItems
            self.method = method
            self.bodyData = bodyData
        }
    }

    private let session: URLSession
    /// 搜索接口是同步阻塞的，遍历所有站点搜索需要较长时间，单独设置超时。
    private let searchSession: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.searchSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)

            let searchConfig = URLSessionConfiguration.ephemeral
            searchConfig.timeoutIntervalForRequest = 120
            searchConfig.timeoutIntervalForResource = 180
            self.searchSession = URLSession(configuration: searchConfig)
        }
    }

    func requestMediaDetail(
        baseURLString: String,
        token: String,
        mediaID: String,
        typeName: String,
        title: String?,
        year: String?
    ) async throws -> MPMediaDetailDTO {
        try await requestDecodable(
            MPMediaDetailDTO.self,
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/media/\(mediaID)",
                queryItems: Self.compactQueryItems([
                    URLQueryItem(name: "type_name", value: typeName),
                    URLQueryItem(name: "title", value: title),
                    URLQueryItem(name: "year", value: year)
                ])
            )
        )
    }

    func requestCredits(
        baseURLString: String,
        token: String,
        mediaID: String,
        typeName: String
    ) async throws -> MPMediaPersonListDTO {
        let route: Route

        if let prefixAndValue = Self.parseMediaIdentifier(mediaID) {
            switch prefixAndValue.prefix {
            case "tmdb":
                route = Route(path: "api/v1/tmdb/credits/\(prefixAndValue.value)/\(typeName)")
            case "douban":
                route = Route(path: "api/v1/douban/credits/\(prefixAndValue.value)/\(typeName)")
            case "bangumi":
                route = Route(path: "api/v1/bangumi/credits/\(prefixAndValue.value)")
            default:
                return []
            }
        } else {
            return []
        }

        return try await requestDecodable(
            MPMediaPersonListDTO.self,
            baseURLString: baseURLString,
            token: token,
            route: route
        )
    }

    func requestSearchResults(
        baseURLString: String,
        token: String,
        mediaID: String,
        mediaType: String?,
        title: String?,
        year: String?,
        season: String?
    ) async throws -> [MPSearchResultWithRawDTO] {
        // 1. 获取原始 Data
        let data = try await requestData(
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/search/media/\(mediaID)",
                queryItems: Self.compactQueryItems([
                    URLQueryItem(name: "mtype", value: mediaType),
                    URLQueryItem(name: "area", value: "title"),
                    URLQueryItem(name: "title", value: title),
                    URLQueryItem(name: "year", value: year),
                    URLQueryItem(name: "season", value: season)
                ])
            ),
            sessionOverride: searchSession
        )

        // 2. 手动解析 JSON — 处理 Response 信封 {success, data: [...]} 或直接数组 [...]
        let topArray: [[String: Any]]

        if let parsed = try? JSONSerialization.jsonObject(with: data) {
            if let array = parsed as? [[String: Any]] {
                // 直接数组格式
                topArray = array
            } else if let envelope = parsed as? [String: Any],
                      let dataArray = envelope["data"] as? [[String: Any]] {
                // Response 信封格式: {success: true, data: [...]}
                topArray = dataArray
            } else {
                // 降级：尝试用 Codable 解码
                let contexts = try JSONDecoder().decode(MPSearchContextListDTO.self, from: data)
                return contexts.compactMap { ctx in
                    guard let dto = ctx.torrentInfo else { return nil }
                    let fallbackData = try? JSONEncoder().encode(dto)
                    return MPSearchResultWithRawDTO(torrentInfo: dto, rawTorrentInfoJSON: fallbackData ?? Data())
                }
            }
        } else {
            let contexts = try JSONDecoder().decode(MPSearchContextListDTO.self, from: data)
            return contexts.compactMap { ctx in
                guard let dto = ctx.torrentInfo else { return nil }
                let fallbackData = try? JSONEncoder().encode(dto)
                return MPSearchResultWithRawDTO(torrentInfo: dto, rawTorrentInfoJSON: fallbackData ?? Data())
            }
        }

        let decoder = JSONDecoder()
        var results: [MPSearchResultWithRawDTO] = []

        for contextDict in topArray {
            guard let torrentInfoDict = contextDict["torrent_info"] as? [String: Any] else { continue }

            // 序列化原始 torrent_info 字典为 Data（保留所有字段）
            guard let rawJSON = try? JSONSerialization.data(withJSONObject: torrentInfoDict) else { continue }

            // 从同一份 Data 解码类型化 DTO
            guard let dto = try? decoder.decode(MPTorrentInfoDTO.self, from: rawJSON) else { continue }

            results.append(MPSearchResultWithRawDTO(torrentInfo: dto, rawTorrentInfoJSON: rawJSON))
        }

        return results
    }

    func requestSubscription(
        baseURLString: String,
        token: String,
        mediaID: String,
        season: Int?,
        title: String?
    ) async throws -> MPSubscribeDTO {
        try await requestDecodable(
            MPSubscribeDTO.self,
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/subscribe/media/\(mediaID)",
                queryItems: Self.compactQueryItems([
                    season.map { URLQueryItem(name: "season", value: String($0)) },
                    URLQueryItem(name: "title", value: title)
                ])
            )
        )
    }

    func requestDownloadClients(
        baseURLString: String,
        token: String
    ) async throws -> MPDownloadClientListDTO {
        try await requestDecodable(
            MPDownloadClientListDTO.self,
            baseURLString: baseURLString,
            token: token,
            route: Route(path: "api/v1/download/clients")
        )
    }

    /// POST /api/v1/download/add — 添加下载任务
    /// `torrentInfoRawJSON` 是搜索时保存的原始 torrent_info JSON Data，
    /// 保留了 enclosure、site_cookie 等所有字段，确保 MoviePilot 能正确下载。
    func requestDownloadAdd(
        baseURLString: String,
        token: String,
        torrentInfoRawJSON: Data,
        downloader: String?,
        savePath: String?
    ) async throws -> MoviePilotActionResponseDTO {
        // 将原始 torrent_info 反序列化为字典
        guard let torrentInfoDict = try? JSONSerialization.jsonObject(with: torrentInfoRawJSON) as? [String: Any] else {
            throw URLError(.cannotDecodeContentData)
        }

        // 组装请求体
        var body: [String: Any] = ["torrent_in": torrentInfoDict]
        if let downloader, !downloader.isEmpty {
            body["downloader"] = downloader
        }
        if let savePath, !savePath.isEmpty {
            body["save_path"] = savePath
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        return try await requestActionResponse(
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/download/add",
                method: .post,
                bodyData: bodyData
            )
        )
    }

    func requestMediaCategories(
        baseURLString: String,
        token: String
    ) async throws -> [String: String] {
        let data = try await requestData(
            baseURLString: baseURLString,
            token: token,
            route: Route(path: "api/v1/media/category")
        )

        return try Self.decodeMediaCategories(from: data)
    }

    func requestSites(
        baseURLString: String,
        token: String
    ) async throws -> MPSiteListDTO {
        try await requestDecodable(
            MPSiteListDTO.self,
            baseURLString: baseURLString,
            token: token,
            route: Route(path: "api/v1/site/")
        )
    }

    func createSubscription(
        baseURLString: String,
        token: String,
        payload: MPSubscribeDTO
    ) async throws -> MoviePilotActionResponseDTO {
        try await requestActionResponse(
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/subscribe/",
                method: .post,
                bodyData: try JSONEncoder().encode(payload)
            )
        )
    }

    func updateSubscription(
        baseURLString: String,
        token: String,
        payload: MPSubscribeDTO
    ) async throws -> MoviePilotActionResponseDTO {
        try await requestActionResponse(
            baseURLString: baseURLString,
            token: token,
            route: Route(
                path: "api/v1/subscribe/",
                method: .put,
                bodyData: try JSONEncoder().encode(payload)
            )
        )
    }

    private func requestDecodable<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        baseURLString: String,
        token: String,
        route: Route,
        sessionOverride: URLSession? = nil
    ) async throws -> Response {
        let data = try await requestData(
            baseURLString: baseURLString,
            token: token,
            route: route,
            sessionOverride: sessionOverride
        )
        return try decodeDirectResponse(responseType, from: data)
    }

    private func requestActionResponse(
        baseURLString: String,
        token: String,
        route: Route
    ) async throws -> MoviePilotActionResponseDTO {
        let data = try await requestData(
            baseURLString: baseURLString,
            token: token,
            route: route
        )
        return try decodeActionResponse(from: data)
    }

    private func requestData(
        baseURLString: String,
        token: String,
        route: Route,
        sessionOverride: URLSession? = nil
    ) async throws -> Data {
        guard let normalizedBaseURL = MoviePilotURLNormalizer.normalize(baseURLString),
              let baseURL = URL(string: normalizedBaseURL) else {
            throw URLError(.badURL)
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var lastError: Error?

        for authenticationMode in AuthenticationMode.allCases {
            do {
                return try await requestData(
                    baseURL: baseURL,
                    token: trimmedToken,
                    route: route,
                    authenticationMode: authenticationMode,
                    sessionOverride: sessionOverride
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotDecodeContentData)
    }

    private func requestData(
        baseURL: URL,
        token: String,
        route: Route,
        authenticationMode: AuthenticationMode,
        sessionOverride: URLSession? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(route.path),
            resolvingAgainstBaseURL: false
        )

        var queryItems = route.queryItems
        switch authenticationMode {
        case .bearerHeader, .apiKeyHeader:
            break
        case .queryAPIKey:
            queryItems.append(URLQueryItem(name: "apikey", value: token))
        case .queryToken:
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let requestURL = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = route.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if route.bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        switch authenticationMode {
        case .bearerHeader:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .apiKeyHeader:
            request.setValue(token, forHTTPHeaderField: "X-API-KEY")
        case .queryAPIKey, .queryToken:
            break
        }

        request.httpBody = route.bodyData

        let (data, response) = try await (sessionOverride ?? session).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(MoviePilotAPIErrorPayload.self, from: data),
               let detail = apiError.detail,
               !detail.isEmpty {
                throw NSError(
                    domain: "MoviePilotMediaDetailAPIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                )
            }

            if let message = Self.extractResponseMessage(from: data) {
                throw NSError(
                    domain: "MoviePilotMediaDetailAPIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            throw NSError(
                domain: "MoviePilotMediaDetailAPIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)]
            )
        }

        return data
    }

    private func decodeDirectResponse<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        from data: Data
    ) throws -> Response {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode(Response.self, from: data) {
            return direct
        }

        if let envelope = try? decoder.decode(MoviePilotResponseEnvelope<Response>.self, from: data),
           let payload = envelope.data {
            return payload
        }

        if let message = Self.extractFailureMessage(from: data) {
            throw NSError(
                domain: "MoviePilotMediaDetailAPIClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func decodeActionResponse(from data: Data) throws -> MoviePilotActionResponseDTO {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode(MoviePilotActionResponseDTO.self, from: data) {
            return direct
        }

        if let envelope = try? decoder.decode(MoviePilotResponseEnvelope<MPSubscriptionMutationDataDTO>.self, from: data),
           let success = envelope.success {
            return MoviePilotActionResponseDTO(success: success, message: envelope.message)
        }

        if let envelope = try? decoder.decode(MoviePilotResponseEnvelope<[String: String]>.self, from: data),
           let success = envelope.success {
            return MoviePilotActionResponseDTO(success: success, message: envelope.message)
        }

        if let message = Self.extractResponseMessage(from: data) {
            return MoviePilotActionResponseDTO(success: false, message: message)
        }

        return try decoder.decode(MoviePilotActionResponseDTO.self, from: data)
    }

    private nonisolated static func compactQueryItems(_ items: [URLQueryItem?]) -> [URLQueryItem] {
        items.compactMap { item in
            guard let item else { return nil }
            let trimmedValue = item.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedValue.isEmpty else { return nil }
            return URLQueryItem(name: item.name, value: trimmedValue)
        }
    }

    private nonisolated static func parseMediaIdentifier(_ mediaID: String) -> (prefix: String, value: String)? {
        let components = mediaID.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        return (components[0].lowercased(), components[1])
    }

    private nonisolated static func decodeMediaCategories(from data: Data) throws -> [String: String] {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }

        if let envelope = try? JSONDecoder().decode(MoviePilotResponseEnvelope<[String: String]>.self, from: data),
           let payload = envelope.data {
            return payload
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        if let object = jsonObject as? [String: Any] {
            var result: [String: String] = [:]
            flattenCategories(prefix: nil, object: object, into: &result)
            return result
        }

        return [:]
    }

    private nonisolated static func flattenCategories(
        prefix: String?,
        object: [String: Any],
        into result: inout [String: String]
    ) {
        for (key, value) in object {
            let composedKey = if let prefix, !prefix.isEmpty {
                "\(prefix)/\(key)"
            } else {
                key
            }

            switch value {
            case let stringValue as String:
                result[composedKey] = stringValue
            case let numberValue as NSNumber:
                result[composedKey] = numberValue.stringValue
            case let nestedObject as [String: Any]:
                flattenCategories(prefix: composedKey, object: nestedObject, into: &result)
            default:
                continue
            }
        }
    }

    private nonisolated static func extractFailureMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = object["success"] as? Bool,
              success == false else {
            return nil
        }

        return extractResponseMessage(from: data) ?? "请求失败"
    }

    private nonisolated static func extractResponseMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }

        return nil
    }
}
