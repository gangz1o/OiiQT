import Foundation

actor MoviePilotAPIClient {
    static let shared = MoviePilotAPIClient()

    private enum AuthenticationMode: CaseIterable {
        case header
        case bearerHeader
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

    func fetchCurrentUser(baseURLString: String, token: String) async throws -> MoviePilotCurrentUser {
        guard let normalizedBaseURL = await MainActor.run(body: {
            MoviePilotURLNormalizer.normalize(baseURLString)
        }),
              let baseURL = URL(string: normalizedBaseURL) else {
            throw URLError(.badURL)
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var lastError: Error?

        for mode in AuthenticationMode.allCases {
            do {
                return try await fetchCurrentUser(
                    baseURL: baseURL,
                    token: trimmedToken,
                    authenticationMode: mode
                )
            } catch {
                guard MoviePilotResponseDecoder.shouldRetryAuthentication(error) else { throw error }
                lastError = error
            }
        }

        throw lastError ?? URLError(.userAuthenticationRequired)
    }

    private func fetchCurrentUser(
        baseURL: URL,
        token: String,
        authenticationMode: AuthenticationMode
    ) async throws -> MoviePilotCurrentUser {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/user/current"), resolvingAgainstBaseURL: false)
        switch authenticationMode {
        case .header, .bearerHeader:
            components?.queryItems = nil
        case .queryAPIKey:
            components?.queryItems = [URLQueryItem(name: "apikey", value: token)]
        case .queryToken:
            components?.queryItems = [URLQueryItem(name: "token", value: token)]
        }

        guard let requestURL = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticationMode == .header {
            request.setValue(token, forHTTPHeaderField: "X-API-KEY")
        } else if authenticationMode == .bearerHeader {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let payload = try MoviePilotResponseDecoder.responseData(data, response: httpResponse)
        return try MoviePilotResponseDecoder.decode(MoviePilotCurrentUser.self, from: payload)
    }
}
