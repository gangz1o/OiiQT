import Foundation

enum RateLimitCapability: Equatable {
    case full
    case qbTransferOnly

    var supportsAdvancedQBControls: Bool {
        self != .qbTransferOnly
    }
}

struct RateLimitLoadResult {
    let settings: RateLimitSettings
    let capability: RateLimitCapability
}

final class ServerRateLimitManager {
    static let shared = ServerRateLimitManager()
    private let browserUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    func load(for server: ServerConfig) async throws -> RateLimitLoadResult {
        switch server.type {
        case .qBittorrent:
            return try await loadQBittorrent(for: server)
        case .transmission:
            return try await loadTransmission(for: server)
        }
    }

    func save(_ settings: RateLimitSettings, for server: ServerConfig, capability: RateLimitCapability) async throws {
        let normalized = settings.normalized()

        switch server.type {
        case .qBittorrent:
            switch capability {
            case .full:
                do {
                    try await saveQBittorrent(normalized, for: server)
                } catch where isQBAppPermissionDenied(error) {
                    try await saveQBittorrentTransferOnly(normalized, for: server)
                }
            case .qbTransferOnly:
                try await saveQBittorrentTransferOnly(normalized, for: server)
            }
        case .transmission:
            try await saveTransmission(normalized, for: server)
        }
    }

    // MARK: - qBittorrent

    private func loadQBittorrent(for server: ServerConfig) async throws -> RateLimitLoadResult {
        let session = makeSession(allowInsecureSSL: server.allowInsecureSSL)
        let baseURL = normalizedBaseURL(server: server)

        try await qbLogin(server: server, baseURL: baseURL, session: session)

        let preferencesData: Data
        do {
            preferencesData = try await qbRequest(
                server: server,
                session: session,
                url: qbAPIURL(server: server, baseURL: baseURL, path: "app/preferences"),
                method: "GET"
            )
        } catch where isQBAppPermissionDenied(error) {
            return try await loadQBittorrentTransferOnly(server: server, session: session, baseURL: baseURL)
        }
        let preferences = try parseJSONObject(preferencesData)

        let speedModeData = try? await qbRequest(
            server: server,
            session: session,
            url: qbAPIURL(server: server, baseURL: baseURL, path: "transfer/speedLimitsMode"),
            method: "GET"
        )
        let speedMode = speedModeData
            .flatMap { Int(String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? 0

        let dlLimitBytes = intValue(preferences["dl_limit"]) ?? 0
        let upLimitBytes = intValue(preferences["up_limit"]) ?? 0
        let altDlBytes = intValue(preferences["alt_dl_limit"]) ?? 0
        let altUpBytes = intValue(preferences["alt_up_limit"]) ?? 0

        let fromHour = intValue(preferences["schedule_from_hour"]) ?? 0
        let fromMin = intValue(preferences["schedule_from_min"]) ?? 0
        let toHour = intValue(preferences["schedule_to_hour"]) ?? 0
        let toMin = intValue(preferences["schedule_to_min"]) ?? 0

        let schedulerEnabled = boolValue(preferences["scheduler_enabled"]) ?? false
        let schedulerDaysRaw = intValue(preferences["scheduler_days"]) ?? 0

        var settings = RateLimitSettings()
        settings.globalDownloadEnabled = dlLimitBytes > 0
        settings.globalDownloadKBps = bytesToKBps(dlLimitBytes)
        settings.globalUploadEnabled = upLimitBytes > 0
        settings.globalUploadKBps = bytesToKBps(upLimitBytes)

        settings.alternativeEnabled = speedMode == 1
        settings.alternativeDownloadEnabled = altDlBytes > 0
        settings.alternativeDownloadKBps = bytesToKBps(altDlBytes)
        settings.alternativeUploadEnabled = altUpBytes > 0
        settings.alternativeUploadKBps = bytesToKBps(altUpBytes)

        settings.scheduleEnabled = schedulerEnabled
        settings.scheduleStartMinutes = minuteOfDay(hour: fromHour, minute: fromMin)
        settings.scheduleEndMinutes = minuteOfDay(hour: toHour, minute: toMin)
        settings.scheduleWeekdays = decodeQBSchedulerDays(schedulerDaysRaw)

        return RateLimitLoadResult(settings: settings.normalized(), capability: .full)
    }

    private func loadQBittorrentTransferOnly(
        server: ServerConfig,
        session: URLSession,
        baseURL: String
    ) async throws -> RateLimitLoadResult {
        let dlBytes = try await qbFetchGlobalLimitBytes(
            server: server,
            session: session,
            baseURL: baseURL,
            endpoint: "transfer/downloadLimit"
        )
        let upBytes = try await qbFetchGlobalLimitBytes(
            server: server,
            session: session,
            baseURL: baseURL,
            endpoint: "transfer/uploadLimit"
        )

        var settings = RateLimitSettings()
        settings.globalDownloadEnabled = dlBytes > 0
        settings.globalDownloadKBps = bytesToKBps(dlBytes)
        settings.globalUploadEnabled = upBytes > 0
        settings.globalUploadKBps = bytesToKBps(upBytes)
        settings.alternativeEnabled = false
        settings.scheduleEnabled = false

        return RateLimitLoadResult(settings: settings.normalized(), capability: .qbTransferOnly)
    }

    private func saveQBittorrent(_ settings: RateLimitSettings, for server: ServerConfig) async throws {
        let session = makeSession(allowInsecureSSL: server.allowInsecureSSL)
        let baseURL = normalizedBaseURL(server: server)

        try await qbLogin(server: server, baseURL: baseURL, session: session)

        let fromHour = settings.scheduleStartMinutes / 60
        let fromMin = settings.scheduleStartMinutes % 60
        let toHour = settings.scheduleEndMinutes / 60
        let toMin = settings.scheduleEndMinutes % 60

        let payload: [String: Any] = [
            "dl_limit": settings.globalDownloadEnabled ? kbpsToBytes(settings.globalDownloadKBps) : 0,
            "up_limit": settings.globalUploadEnabled ? kbpsToBytes(settings.globalUploadKBps) : 0,
            "alt_dl_limit": settings.alternativeDownloadEnabled ? kbpsToBytes(settings.alternativeDownloadKBps) : 0,
            "alt_up_limit": settings.alternativeUploadEnabled ? kbpsToBytes(settings.alternativeUploadKBps) : 0,
            "scheduler_enabled": settings.alternativeEnabled && settings.scheduleEnabled,
            "schedule_from_hour": fromHour,
            "schedule_from_min": fromMin,
            "schedule_to_hour": toHour,
            "schedule_to_min": toMin,
            "scheduler_days": encodeQBSchedulerDays(settings.scheduleWeekdays)
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TorrentClientError.apiError("qB setPreferences payload encoding failed")
        }

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "json", value: jsonString)]
        let bodyData = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        _ = try await qbRequest(
            server: server,
            session: session,
            url: qbAPIURL(server: server, baseURL: baseURL, path: "app/setPreferences"),
            method: "POST",
            body: bodyData,
            contentType: "application/x-www-form-urlencoded; charset=UTF-8"
        )

        if let currentModeData = try? await qbRequest(
            server: server,
            session: session,
            url: qbAPIURL(server: server, baseURL: baseURL, path: "transfer/speedLimitsMode"),
            method: "GET"
        ) {
            let currentMode = Int(String(decoding: currentModeData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let desiredMode = settings.alternativeEnabled ? 1 : 0

            if currentMode != desiredMode {
                _ = try? await qbRequest(
                    server: server,
                    session: session,
                    url: qbAPIURL(server: server, baseURL: baseURL, path: "transfer/toggleSpeedLimitsMode"),
                    method: "POST"
                )
            }
        }
    }

    private func saveQBittorrentTransferOnly(_ settings: RateLimitSettings, for server: ServerConfig) async throws {
        let session = makeSession(allowInsecureSSL: server.allowInsecureSSL)
        let baseURL = normalizedBaseURL(server: server)

        try await qbLogin(server: server, baseURL: baseURL, session: session)

        let downloadLimitBytes = settings.globalDownloadEnabled ? kbpsToBytes(settings.globalDownloadKBps) : 0
        let uploadLimitBytes = settings.globalUploadEnabled ? kbpsToBytes(settings.globalUploadKBps) : 0

        try await qbSetGlobalLimitBytes(
            server: server,
            session: session,
            baseURL: baseURL,
            endpoint: "transfer/setDownloadLimit",
            limitBytes: downloadLimitBytes
        )
        try await qbSetGlobalLimitBytes(
            server: server,
            session: session,
            baseURL: baseURL,
            endpoint: "transfer/setUploadLimit",
            limitBytes: uploadLimitBytes
        )
    }

    private func qbLogin(server: ServerConfig, baseURL: String, session: URLSession) async throws {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "username", value: server.username),
            URLQueryItem(name: "password", value: server.password)
        ]
        let data = components.percentEncodedQuery?.data(using: .utf8)

        guard let url = URL(string: qbAPIURL(server: server, baseURL: baseURL, path: "auth/login")) else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(normalizedBaseURL(server: server), forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        guard httpResponse.statusCode == 200 else {
            throw TorrentClientError.authenticationFailed
        }

        let text = String(decoding: responseData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text == "Ok." else {
            throw TorrentClientError.authenticationFailed
        }
    }

    private func qbRequest(
        server: ServerConfig,
        session: URLSession,
        url: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        guard let endpoint = URL(string: url) else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue(normalizedBaseURL(server: server), forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        if httpResponse.statusCode == 403, endpoint.path.contains("/app/") {
            // Some reverse proxies/qB builds are stricter on Referer for app/*.
            // Retry once with a minimal header set before treating it as permission failure.
            var relaxed = request
            relaxed.setValue(nil, forHTTPHeaderField: "Referer")

            let (retryData, retryResponse) = try await session.data(for: relaxed)
            if let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 {
                return retryData
            }
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            throw TorrentClientError.authenticationFailed
        case 403:
            let path = endpoint.path.isEmpty ? url : endpoint.path
            throw TorrentClientError.apiError("qB API denied (403): \(path). Even with admin rights, reverse proxy/cookie policy may block app/* endpoints")
        default:
            let bodyText = String(decoding: data, as: UTF8.self)
            throw TorrentClientError.apiError("qB API failed (\(httpResponse.statusCode)): \(bodyText)")
        }
    }

    // MARK: - Transmission

    private func loadTransmission(for server: ServerConfig) async throws -> RateLimitLoadResult {
        let session = makeSession(allowInsecureSSL: server.allowInsecureSSL)
        var sessionID: String?

        let data = try await transmissionRequest(
            server: server,
            session: session,
            sessionID: &sessionID,
            method: "session-get",
            arguments: nil
        )

        let response = try JSONDecoder().decode(TransmissionEnvelope<TransmissionSessionSettings>.self, from: data)
        guard response.result == "success", let args = response.arguments else {
            throw TorrentClientError.apiError("Transmission session-get failed")
        }

        var settings = RateLimitSettings()
        settings.globalDownloadEnabled = args.speedLimitDownEnabled
        settings.globalDownloadKBps = max(args.speedLimitDown, 0)
        settings.globalUploadEnabled = args.speedLimitUpEnabled
        settings.globalUploadKBps = max(args.speedLimitUp, 0)

        settings.alternativeEnabled = args.altSpeedEnabled
        settings.alternativeDownloadEnabled = args.altSpeedDown > 0
        settings.alternativeDownloadKBps = max(args.altSpeedDown, 0)
        settings.alternativeUploadEnabled = args.altSpeedUp > 0
        settings.alternativeUploadKBps = max(args.altSpeedUp, 0)

        settings.scheduleEnabled = args.altSpeedTimeEnabled
        settings.scheduleStartMinutes = RateLimitSettings.clampedMinute(args.altSpeedTimeBegin)
        settings.scheduleEndMinutes = RateLimitSettings.clampedMinute(args.altSpeedTimeEnd)
        settings.scheduleWeekdays = decodeTransmissionDayMask(args.altSpeedTimeDay)

        return RateLimitLoadResult(settings: settings.normalized(), capability: .full)
    }

    private func saveTransmission(_ settings: RateLimitSettings, for server: ServerConfig) async throws {
        let session = makeSession(allowInsecureSSL: server.allowInsecureSSL)
        var sessionID: String?

        let arguments: [String: Any] = [
            "speed-limit-down-enabled": settings.globalDownloadEnabled,
            "speed-limit-down": max(settings.globalDownloadKBps, 0),
            "speed-limit-up-enabled": settings.globalUploadEnabled,
            "speed-limit-up": max(settings.globalUploadKBps, 0),
            "alt-speed-enabled": settings.alternativeEnabled,
            "alt-speed-down": settings.alternativeDownloadEnabled ? max(settings.alternativeDownloadKBps, 0) : 0,
            "alt-speed-up": settings.alternativeUploadEnabled ? max(settings.alternativeUploadKBps, 0) : 0,
            "alt-speed-time-enabled": settings.alternativeEnabled && settings.scheduleEnabled,
            "alt-speed-time-begin": settings.scheduleStartMinutes,
            "alt-speed-time-end": settings.scheduleEndMinutes,
            "alt-speed-time-day": encodeTransmissionDayMask(settings.scheduleWeekdays)
        ]

        let data = try await transmissionRequest(
            server: server,
            session: session,
            sessionID: &sessionID,
            method: "session-set",
            arguments: arguments
        )

        let response = try JSONDecoder().decode(TransmissionEnvelope<EmptyTransmissionArguments>.self, from: data)
        guard response.result == "success" else {
            throw TorrentClientError.apiError("Transmission session-set failed")
        }
    }

    private func transmissionRequest(
        server: ServerConfig,
        session: URLSession,
        sessionID: inout String?,
        method: String,
        arguments: [String: Any]?
    ) async throws -> Data {
        guard let rpcURL = transmissionRPCURL(server: server) else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeaderValue(username: server.username, password: server.password), forHTTPHeaderField: "Authorization")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
        }

        let body: [String: Any] = [
            "method": method,
            "arguments": arguments ?? [:]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 409,
           let newSessionID = httpResponse.value(forHTTPHeaderField: "X-Transmission-Session-Id") {
            sessionID = newSessionID
            request.setValue(newSessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            (data, response) = try await session.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw TorrentClientError.authenticationFailed
        default:
            throw TorrentClientError.apiError("Transmission RPC failed (\(httpResponse.statusCode)): \(method)")
        }
    }

    // MARK: - Shared Helpers

    private func makeSession(allowInsecureSSL: Bool) -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        let delegate = NetworkManager(allowInsecureSSL: allowInsecureSSL)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private func normalizedBaseURL(server: ServerConfig) -> String {
        "\(server.urlScheme)://\(server.sanitizedAddress):\(server.port)"
    }

    private func transmissionRPCURL(server: ServerConfig) -> URL? {
        let path = server.rpcPath.hasPrefix("/") ? server.rpcPath : "/\(server.rpcPath)"
        return URL(string: "\(normalizedBaseURL(server: server))\(path)")
    }

    private func qbAPIPathPrefix(server: ServerConfig) -> String {
        let trimmed = server.rpcPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/api/v2" }
        let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return normalized == "/transmission/rpc" ? "/api/v2" : normalized
    }

    private func qbAPIURL(server: ServerConfig, baseURL: String, path: String) -> String {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return "\(baseURL)\(qbAPIPathPrefix(server: server))\(normalizedPath)"
    }

    private func basicAuthHeaderValue(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw TorrentClientError.decodingError
        }
        return dict
    }

    private func qbFetchGlobalLimitBytes(
        server: ServerConfig,
        session: URLSession,
        baseURL: String,
        endpoint: String
    ) async throws -> Int {
        let data = try await qbRequest(
            server: server,
            session: session,
            url: qbAPIURL(server: server, baseURL: baseURL, path: endpoint),
            method: "GET"
        )
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text) ?? 0
    }

    private func qbSetGlobalLimitBytes(
        server: ServerConfig,
        session: URLSession,
        baseURL: String,
        endpoint: String,
        limitBytes: Int
    ) async throws {
        let body = "limit=\(max(limitBytes, 0))".data(using: .utf8)
        _ = try await qbRequest(
            server: server,
            session: session,
            url: qbAPIURL(server: server, baseURL: baseURL, path: endpoint),
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded; charset=UTF-8"
        )
    }

    private func isQBAppPermissionDenied(_ error: Error) -> Bool {
        guard case let TorrentClientError.apiError(message) = error else {
            return false
        }
        return message.contains("(403)") && message.contains("/app/")
    }

    private func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? String { return Int(v) }
        if let v = any as? NSNumber { return v.intValue }
        return nil
    }

    private func boolValue(_ any: Any?) -> Bool? {
        if let v = any as? Bool { return v }
        if let v = any as? NSNumber { return v.boolValue }
        if let v = any as? String {
            let lower = v.lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return nil
    }

    private func kbpsToBytes(_ kbps: Int) -> Int {
        max(kbps, 0) * 1024
    }

    private func bytesToKBps(_ bytes: Int) -> Int {
        max(bytes, 0) / 1024
    }

    private func minuteOfDay(hour: Int, minute: Int) -> Int {
        let h = max(0, min(23, hour))
        let m = max(0, min(59, minute))
        return h * 60 + m
    }

    private func decodeTransmissionDayMask(_ value: Int) -> Set<Int> {
        let mask = value & 0b111_1111
        if mask == 0 {
            return Set(0...6)
        }

        var result: Set<Int> = []
        for day in 0...6 {
            if (mask & (1 << day)) != 0 {
                result.insert(day)
            }
        }
        return result.isEmpty ? Set(0...6) : result
    }

    private func encodeTransmissionDayMask(_ weekdays: Set<Int>) -> Int {
        let clamped = weekdays.filter { (0...6).contains($0) }
        if clamped.isEmpty {
            return 0b111_1111
        }

        return clamped.reduce(0) { partial, day in
            partial | (1 << day)
        }
    }

    private func decodeQBSchedulerDays(_ value: Int) -> Set<Int> {
        switch value {
        case 0:
            return Set(0...6)
        case 1:
            return Set([1, 2, 3, 4, 5])
        case 2:
            return Set([0, 6])
        case 3:
            return Set([1])
        case 4:
            return Set([2])
        case 5:
            return Set([3])
        case 6:
            return Set([4])
        case 7:
            return Set([5])
        case 8:
            return Set([6])
        case 9:
            return Set([0])
        default:
            return decodeTransmissionDayMask(value)
        }
    }

    private func encodeQBSchedulerDays(_ weekdays: Set<Int>) -> Int {
        let normalized = weekdays.filter { (0...6).contains($0) }
        if normalized == Set(0...6) {
            return 0
        }

        if normalized == Set([1, 2, 3, 4, 5]) {
            return 1
        }

        if normalized == Set([0, 6]) {
            return 2
        }

        if normalized.count == 1, let day = normalized.first {
            switch day {
            case 1: return 3
            case 2: return 4
            case 3: return 5
            case 4: return 6
            case 5: return 7
            case 6: return 8
            case 0: return 9
            default: break
            }
        }

        return encodeTransmissionDayMask(normalized)
    }
}

private struct TransmissionEnvelope<T: Decodable>: Decodable {
    let arguments: T?
    let result: String
}

private struct EmptyTransmissionArguments: Decodable {}

private struct TransmissionSessionSettings: Decodable {
    let speedLimitDownEnabled: Bool
    let speedLimitDown: Int
    let speedLimitUpEnabled: Bool
    let speedLimitUp: Int

    let altSpeedEnabled: Bool
    let altSpeedDown: Int
    let altSpeedUp: Int

    let altSpeedTimeEnabled: Bool
    let altSpeedTimeBegin: Int
    let altSpeedTimeEnd: Int
    let altSpeedTimeDay: Int

    enum CodingKeys: String, CodingKey {
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitDown = "speed-limit-down"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case speedLimitUp = "speed-limit-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDay = "alt-speed-time-day"
    }
}
