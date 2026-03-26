import Foundation

nonisolated enum MoviePilotDiscoveryRoute: Sendable, Equatable {
    case recommendSource
    case bangumiCalendar(page: Int = 1, count: Int = 30)
    case doubanShowing(page: Int = 1, count: Int = 30)
    case doubanMovies(page: Int = 1, count: Int = 30, sort: String = "R", tags: String = "")
    case doubanTVs(page: Int = 1, count: Int = 30, sort: String = "R", tags: String = "")
    case doubanMovieTop250(page: Int = 1, count: Int = 30)
    case doubanTVWeeklyChinese(page: Int = 1, count: Int = 30)
    case doubanTVWeeklyGlobal(page: Int = 1, count: Int = 30)
    case doubanTVAnimation(page: Int = 1, count: Int = 30)
    case doubanMovieHot(page: Int = 1, count: Int = 30)
    case doubanTVHot(page: Int = 1, count: Int = 30)
    case tmdbMovies(page: Int = 1, sortBy: String = "popularity.desc")
    case tmdbTVs(page: Int = 1, sortBy: String = "popularity.desc")
    case tmdbTrending(page: Int = 1)

    var path: String {
        switch self {
        case .recommendSource:
            return "api/v1/recommend/source"
        case .bangumiCalendar:
            return "api/v1/recommend/bangumi_calendar"
        case .doubanShowing:
            return "api/v1/recommend/douban_showing"
        case .doubanMovies:
            return "api/v1/recommend/douban_movies"
        case .doubanTVs:
            return "api/v1/recommend/douban_tvs"
        case .doubanMovieTop250:
            return "api/v1/recommend/douban_movie_top250"
        case .doubanTVWeeklyChinese:
            return "api/v1/recommend/douban_tv_weekly_chinese"
        case .doubanTVWeeklyGlobal:
            return "api/v1/recommend/douban_tv_weekly_global"
        case .doubanTVAnimation:
            return "api/v1/recommend/douban_tv_animation"
        case .doubanMovieHot:
            return "api/v1/recommend/douban_movie_hot"
        case .doubanTVHot:
            return "api/v1/recommend/douban_tv_hot"
        case .tmdbTrending:
            return "api/v1/recommend/tmdb_trending"
        case .tmdbMovies:
            return "api/v1/recommend/tmdb_movies"
        case .tmdbTVs:
            return "api/v1/recommend/tmdb_tvs"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .recommendSource:
            return []
        case let .bangumiCalendar(page, count),
             let .doubanShowing(page, count),
             let .doubanMovieTop250(page, count),
             let .doubanTVWeeklyChinese(page, count),
             let .doubanTVWeeklyGlobal(page, count),
             let .doubanTVAnimation(page, count),
             let .doubanMovieHot(page, count),
             let .doubanTVHot(page, count):
            return [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "count", value: String(count))
            ]
        case let .doubanMovies(page, count, sort, tags),
             let .doubanTVs(page, count, sort, tags):
            return [
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "tags", value: tags),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "count", value: String(count))
            ]
        case let .tmdbTrending(page):
            return [URLQueryItem(name: "page", value: String(page))]
        case let .tmdbMovies(page, sortBy),
             let .tmdbTVs(page, sortBy):
            return [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "sort_by", value: sortBy)
            ]
        }
    }

    var fallbackCandidates: [MoviePilotDiscoveryRoute] {
        [self]
    }

    var page: Int {
        switch self {
        case .recommendSource:
            return 1
        case let .bangumiCalendar(page, _),
             let .doubanShowing(page, _),
             let .doubanMovies(page, _, _, _),
             let .doubanTVs(page, _, _, _),
             let .doubanMovieTop250(page, _),
             let .doubanTVWeeklyChinese(page, _),
             let .doubanTVWeeklyGlobal(page, _),
             let .doubanTVAnimation(page, _),
             let .doubanMovieHot(page, _),
             let .doubanTVHot(page, _),
             let .tmdbMovies(page, _),
             let .tmdbTVs(page, _),
             let .tmdbTrending(page):
            return page
        }
    }

    var expectedPageSize: Int {
        switch self {
        case .recommendSource:
            return 0
        case let .bangumiCalendar(_, count),
             let .doubanShowing(_, count),
             let .doubanMovies(_, count, _, _),
             let .doubanTVs(_, count, _, _),
             let .doubanMovieTop250(_, count),
             let .doubanTVWeeklyChinese(_, count),
             let .doubanTVWeeklyGlobal(_, count),
             let .doubanTVAnimation(_, count),
             let .doubanMovieHot(_, count),
             let .doubanTVHot(_, count):
            return count
        case .tmdbMovies, .tmdbTVs, .tmdbTrending:
            return 20
        }
    }

    var supportsPagination: Bool {
        if case .recommendSource = self {
            return false
        }
        return true
    }

    func withPage(_ page: Int) -> MoviePilotDiscoveryRoute {
        switch self {
        case .recommendSource:
            return self
        case let .bangumiCalendar(_, count):
            return .bangumiCalendar(page: page, count: count)
        case let .doubanShowing(_, count):
            return .doubanShowing(page: page, count: count)
        case let .doubanMovies(_, count, sort, tags):
            return .doubanMovies(page: page, count: count, sort: sort, tags: tags)
        case let .doubanTVs(_, count, sort, tags):
            return .doubanTVs(page: page, count: count, sort: sort, tags: tags)
        case let .doubanMovieTop250(_, count):
            return .doubanMovieTop250(page: page, count: count)
        case let .doubanTVWeeklyChinese(_, count):
            return .doubanTVWeeklyChinese(page: page, count: count)
        case let .doubanTVWeeklyGlobal(_, count):
            return .doubanTVWeeklyGlobal(page: page, count: count)
        case let .doubanTVAnimation(_, count):
            return .doubanTVAnimation(page: page, count: count)
        case let .doubanMovieHot(_, count):
            return .doubanMovieHot(page: page, count: count)
        case let .doubanTVHot(_, count):
            return .doubanTVHot(page: page, count: count)
        case let .tmdbMovies(_, sortBy):
            return .tmdbMovies(page: page, sortBy: sortBy)
        case let .tmdbTVs(_, sortBy):
            return .tmdbTVs(page: page, sortBy: sortBy)
        case .tmdbTrending:
            return .tmdbTrending(page: page)
        }
    }
}

actor MoviePilotDiscoveryAPIClient {
    static let shared = MoviePilotDiscoveryAPIClient()

    private enum AuthenticationMode: CaseIterable {
        case bearerHeader
        case apiKeyHeader
        case queryAPIKey
        case queryToken
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func requestMediaList(
        baseURLString: String,
        token: String,
        route: MoviePilotDiscoveryRoute
    ) async throws -> MPMediaListDTO {
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
            for candidateRoute in route.fallbackCandidates {
                do {
                    let data = try await requestData(
                        baseURL: baseURL,
                        token: trimmedToken,
                        route: candidateRoute,
                        authenticationMode: authenticationMode
                    )
                    return try decodeResponse(MPMediaListDTO.self, from: data)
                } catch {
                    lastError = error
                    if shouldContinueTryingRoutes(after: error) {
                        continue
                    }
                }
            }
        }

        throw lastError ?? URLError(.cannotDecodeContentData)
    }

    func requestMediaSearchResults(
        baseURLString: String,
        token: String,
        title: String,
        page: Int = 1,
        count: Int = 20,
        type: String = "media"
    ) async throws -> MPMediaListDTO {
        guard let normalizedBaseURL = MoviePilotURLNormalizer.normalize(baseURLString),
              let baseURL = URL(string: normalizedBaseURL) else {
            throw URLError(.badURL)
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        guard !trimmedTitle.isEmpty else {
            throw URLError(.badURL)
        }

        let queryItems = [
            URLQueryItem(name: "title", value: trimmedTitle),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "count", value: String(count))
        ]

        var lastError: Error?

        for authenticationMode in AuthenticationMode.allCases {
            do {
                let data = try await requestData(
                    baseURL: baseURL,
                    token: trimmedToken,
                    path: "api/v1/media/search",
                    queryItems: queryItems,
                    authenticationMode: authenticationMode
                )
                return try decodeResponse(MPMediaListDTO.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotDecodeContentData)
    }

    func request<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        baseURLString: String,
        token: String,
        route: MoviePilotDiscoveryRoute
    ) async throws -> Response {
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
                return try await request(
                    responseType,
                    baseURL: baseURL,
                    token: trimmedToken,
                    route: route,
                    authenticationMode: authenticationMode
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.userAuthenticationRequired)
    }

    private func request<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        baseURL: URL,
        token: String,
        route: MoviePilotDiscoveryRoute,
        authenticationMode: AuthenticationMode
    ) async throws -> Response {
        let data = try await requestData(
            baseURL: baseURL,
            token: token,
            route: route,
            authenticationMode: authenticationMode
        )

        return try decodeResponse(responseType, from: data)
    }

    private func requestData(
        baseURL: URL,
        token: String,
        route: MoviePilotDiscoveryRoute,
        authenticationMode: AuthenticationMode
    ) async throws -> Data {
        try await requestData(
            baseURL: baseURL,
            token: token,
            path: route.path,
            queryItems: route.queryItems,
            authenticationMode: authenticationMode
        )
    }

    private func requestData(
        baseURL: URL,
        token: String,
        path: String,
        queryItems baseQueryItems: [URLQueryItem],
        authenticationMode: AuthenticationMode
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )

        var queryItems = baseQueryItems
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
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch authenticationMode {
        case .bearerHeader:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .apiKeyHeader:
            request.setValue(token, forHTTPHeaderField: "X-API-KEY")
        case .queryAPIKey, .queryToken:
            break
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(MoviePilotAPIErrorPayload.self, from: data),
               let detail = apiError.detail,
               !detail.isEmpty {
                throw NSError(
                    domain: "MoviePilotDiscoveryAPIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                )
            }

            throw NSError(
                domain: "MoviePilotDiscoveryAPIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)]
            )
        }

        return data
    }

    private func decodeResponse<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        from data: Data
    ) throws -> Response {
        let decoder = JSONDecoder()

        if let response = try? decoder.decode(responseType, from: data) {
            return response
        }

        if let envelope = try? decoder.decode(MoviePilotResponseEnvelope<Response>.self, from: data) {
            if envelope.success == false {
                throw NSError(
                    domain: "MoviePilotDiscoveryAPIClient",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: envelope.message ?? "MoviePilot 接口返回失败"]
                )
            }
            if let response = envelope.data {
                return response
            }
        }

        if let extractedData = extractWrappedPayloadData(from: data),
           let response = try? decoder.decode(responseType, from: extractedData) {
            return response
        }

        return try decoder.decode(responseType, from: data)
    }

    private func extractWrappedPayloadData(from data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let dataValue = object["data"] {
            if JSONSerialization.isValidJSONObject(dataValue) {
                return try? JSONSerialization.data(withJSONObject: dataValue)
            }
        }

        for key in ["list", "items", "results"] {
            if let value = object[key], JSONSerialization.isValidJSONObject(value) {
                return try? JSONSerialization.data(withJSONObject: value)
            }
        }

        if let dataObject = object["data"] as? [String: Any] {
            for key in ["list", "items", "results"] {
                if let value = dataObject[key], JSONSerialization.isValidJSONObject(value) {
                    return try? JSONSerialization.data(withJSONObject: value)
                }
            }
        }

        return nil
    }

    private func shouldContinueTryingRoutes(after error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "MoviePilotDiscoveryAPIClient" && nsError.code == 404 {
            return true
        }
        return false
    }
}
