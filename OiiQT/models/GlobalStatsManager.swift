//
//  GlobalStatsManager.swift
//  OiiQT
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Observation

struct DashboardServerStorageEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let serverName: String
    let defaultSavePath: String
    let remainingSpace: Int64?
    let totalAllTimeDownloaded: Int64?
    let totalAllTimeUploaded: Int64?
    let connectionState: ServerConnectionState
    let statusMessage: String

    var isOnline: Bool {
        connectionState == .online
    }
}

struct GlobalStatsSnapshot: Sendable {
    var totalSeedingCount: Int = 0
    var totalDownloadingCount: Int = 0
    var totalBandwidth: Int64 = 0
    var totalRemainingSpace: Int64 = 0
    var totalAllTimeDownloaded: Int64 = 0
    var totalAllTimeUploaded: Int64 = 0
    var onlineServerCount: Int = 0
    var failedServerCount: Int = 0
    var hasConnectionIssue: Bool = false
    var hasReliableTransferTotals: Bool = false
    var serverStorage: [DashboardServerStorageEntry] = []
    var lastUpdatedAt: Date?
}

func formatStorageSize(_ bytes: Int64) -> String {
    if bytes <= 0 { return "0 B" }

    let value = Double(bytes)
    let gb = 1024.0 * 1024.0 * 1024.0
    let tb = gb * 1024
    let pb = tb * 1024

    if value >= pb {
        return formatStorageValue(value / pb, unit: "PB")
    }
    if value >= tb {
        return formatStorageValue(value / tb, unit: "TB")
    }

    return formatBytes(bytes)
}

private func formatStorageValue(_ value: Double, unit: String) -> String {
    let decimals: Int
    if value >= 100 {
        decimals = 0
    } else if value >= 10 {
        decimals = 1
    } else {
        decimals = 2
    }

    return String(format: "%.*f %@", decimals, value, unit)
}

@MainActor
@Observable
final class GlobalStatsManager {
    static let shared = GlobalStatsManager()

    var snapshot = GlobalStatsSnapshot()
    var isRefreshing = false

    private let cacheTTL: TimeInterval = 30
    private var refreshInFlight = false
    private var lastFetchedAt: Date?
    private var lastServerSignature: String = ""
    private var lastKnownStatsByServer: [UUID: GlobalStatsServerSnapshot] = [:]

    private init() {}

    func refresh(servers: [ServerConfig], force: Bool = false, isSilent: Bool = false) async {
        let validServerIDs = Set(servers.map(\.id))
        lastKnownStatsByServer = lastKnownStatsByServer.filter { validServerIDs.contains($0.key) }

        let signature = serverSignature(servers)

        if !force, shouldUseCache(signature: signature) {
            syncCachedConnectionState(from: servers)
            return
        }

        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        for server in servers {
            server.beginConnectionRefresh(isSilent: isSilent)
        }
        defer {
            isRefreshing = false
            refreshInFlight = false
        }

        guard !servers.isEmpty else {
            snapshot = GlobalStatsSnapshot(
                totalSeedingCount: 0,
                totalDownloadingCount: 0,
                totalBandwidth: 0,
                totalRemainingSpace: 0,
                onlineServerCount: 0,
                failedServerCount: 0,
                hasConnectionIssue: false,
                serverStorage: [],
                lastUpdatedAt: Date()
            )
            lastKnownStatsByServer.removeAll()
            lastFetchedAt = Date()
            lastServerSignature = signature
            return
        }

        let endpoints = servers.map(GlobalStatsServerEndpoint.init(server:))
        let fetchResults = await GlobalStatsFetcher.fetchAll(endpoints: endpoints, retryCount: 2)

        applyConnectionState(to: servers, results: fetchResults)
        snapshot = buildSnapshot(servers: servers, results: fetchResults)

        lastFetchedAt = Date()
        lastServerSignature = signature
    }

    private func shouldUseCache(signature: String) -> Bool {
        let hasIncompleteOnlineStorage = snapshot.serverStorage.contains {
            $0.isOnline && ($0.defaultSavePath == "--" || $0.remainingSpace == nil)
        }
        if hasIncompleteOnlineStorage {
            return false
        }

        guard let lastFetchedAt else { return false }
        let age = Date().timeIntervalSince(lastFetchedAt)
        return age < cacheTTL && signature == lastServerSignature
    }

    private func syncCachedConnectionState(from servers: [ServerConfig]) {
        let stateMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0.connectionState) })

        snapshot.serverStorage = snapshot.serverStorage.map { entry in
            let state = stateMap[entry.id] ?? entry.connectionState
            return DashboardServerStorageEntry(
                id: entry.id,
                serverName: entry.serverName,
                defaultSavePath: entry.defaultSavePath,
                remainingSpace: entry.remainingSpace,
                totalAllTimeDownloaded: entry.totalAllTimeDownloaded,
                totalAllTimeUploaded: entry.totalAllTimeUploaded,
                connectionState: state,
                statusMessage: state.statusMessage
            )
        }

        snapshot.onlineServerCount = servers.filter { $0.connectionState == .online }.count
        snapshot.failedServerCount = servers.filter { $0.connectionState == .offline }.count
        snapshot.hasConnectionIssue = !servers.isEmpty && snapshot.onlineServerCount == 0 && snapshot.failedServerCount > 0
    }

    private func applyConnectionState(to servers: [ServerConfig], results: [GlobalServerFetchResult]) {
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.serverID, $0) })

        for server in servers {
            guard let result = resultMap[server.id] else {
                server.registerConnectionFailure()
                continue
            }

            if result.isOnline {
                server.registerConnectionSuccess()
            } else {
                server.registerConnectionFailure()
            }
        }
    }

    private func buildSnapshot(servers: [ServerConfig], results: [GlobalServerFetchResult]) -> GlobalStatsSnapshot {
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.serverID, $0) })

        var totalSeedingCount = 0
        var totalDownloadingCount = 0
        var totalBandwidth: Int64 = 0
        var totalRemainingSpace: Int64 = 0
        var totalAllTimeDownloaded: Int64 = 0
        var totalAllTimeUploaded: Int64 = 0
        var onlineServerCount = 0
        var failedServerCount = 0
        var transferTotalsSourceCount = 0

        var storageRows: [DashboardServerStorageEntry] = []
        storageRows.reserveCapacity(servers.count)

        for server in servers {
            let result = resultMap[server.id]
            if let freshStats = result?.stats {
                lastKnownStatsByServer[server.id] = freshStats
            }

            let cachedStats = lastKnownStatsByServer[server.id]
            let connectionState = server.connectionState
            let isOnline = connectionState == .online
            let effectiveStats = result?.stats ?? (isOnline ? cachedStats : nil)
            let transferTotalsStats = result?.stats ?? cachedStats

            if let transferTotalsStats {
                totalAllTimeDownloaded += max(transferTotalsStats.totalAllTimeDownloaded, 0)
                totalAllTimeUploaded += max(transferTotalsStats.totalAllTimeUploaded, 0)
                transferTotalsSourceCount += 1
            }

            if let stats = effectiveStats, isOnline {
                onlineServerCount += 1
                totalSeedingCount += stats.seedingCount
                totalDownloadingCount += stats.downloadingCount
                totalBandwidth += stats.totalBandwidth
                totalRemainingSpace += stats.remainingSpace

                storageRows.append(
                    DashboardServerStorageEntry(
                        id: server.id,
                        serverName: server.name,
                        defaultSavePath: stats.defaultSavePath,
                        remainingSpace: stats.remainingSpace,
                        totalAllTimeDownloaded: stats.totalAllTimeDownloaded,
                        totalAllTimeUploaded: stats.totalAllTimeUploaded,
                        connectionState: .online,
                        statusMessage: ServerConnectionState.online.statusMessage
                    )
                )
            } else {
                if connectionState == .offline {
                    failedServerCount += 1
                }
                storageRows.append(
                    DashboardServerStorageEntry(
                        id: server.id,
                        serverName: server.name,
                        defaultSavePath: effectiveStats?.defaultSavePath ?? "--",
                        remainingSpace: nil,
                        totalAllTimeDownloaded: transferTotalsStats?.totalAllTimeDownloaded,
                        totalAllTimeUploaded: transferTotalsStats?.totalAllTimeUploaded,
                        connectionState: connectionState,
                        statusMessage: connectionState.statusMessage
                    )
                )
            }
        }

        return GlobalStatsSnapshot(
            totalSeedingCount: totalSeedingCount,
            totalDownloadingCount: totalDownloadingCount,
            totalBandwidth: totalBandwidth,
            totalRemainingSpace: totalRemainingSpace,
            totalAllTimeDownloaded: totalAllTimeDownloaded,
            totalAllTimeUploaded: totalAllTimeUploaded,
            onlineServerCount: onlineServerCount,
            failedServerCount: failedServerCount,
            hasConnectionIssue: onlineServerCount == 0 && failedServerCount > 0,
            hasReliableTransferTotals: transferTotalsSourceCount == servers.count && !servers.isEmpty,
            serverStorage: storageRows,
            lastUpdatedAt: Date()
        )
    }

    private func serverSignature(_ servers: [ServerConfig]) -> String {
        servers
            .map {
                "\($0.id.uuidString)|\($0.type.rawValue)|\($0.address)|\($0.port)|\($0.username)|\($0.useHTTPS)|\($0.rpcPath)|\($0.allowInsecureSSL)|\($0.qbUsesAPIKey)"
            }
            .sorted()
            .joined(separator: "||")
    }
}

private struct GlobalStatsServerSnapshot: Sendable {
    let seedingCount: Int
    let downloadingCount: Int
    let totalBandwidth: Int64
    let remainingSpace: Int64
    let defaultSavePath: String
    let totalAllTimeDownloaded: Int64
    let totalAllTimeUploaded: Int64
}

private struct GlobalServerFetchResult: Sendable {
    let serverID: UUID
    let isOnline: Bool
    let stats: GlobalStatsServerSnapshot?
}

private struct GlobalStatsServerEndpoint: Sendable {
    let id: UUID
    let typeRawValue: String
    let address: String
    let port: Int
    let username: String
    let password: String
    let qbUsesAPIKey: Bool
    let useHTTPS: Bool
    let allowInsecureSSL: Bool
    let rpcPath: String

    var serverType: ServerType {
        ServerType(rawValue: typeRawValue) ?? .qBittorrent
    }

    init(server: ServerConfig) {
        self.id = server.id
        self.typeRawValue = server.type.rawValue
        self.address = server.address
        self.port = server.port
        self.username = server.username
        self.password = server.resolvedPassword
        self.qbUsesAPIKey = server.qbUsesAPIKey
        self.useHTTPS = server.useHTTPS
        self.allowInsecureSSL = server.allowInsecureSSL
        self.rpcPath = server.rpcPath
    }
}

private enum GlobalStatsFetcher {
    private static let standardRequestTimeout: TimeInterval = 30
    private static let heavyPayloadTimeout: TimeInterval = 60

    static func fetchAll(endpoints: [GlobalStatsServerEndpoint], retryCount: Int) async -> [GlobalServerFetchResult] {
        await withTaskGroup(of: GlobalServerFetchResult.self, returning: [GlobalServerFetchResult].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await fetchWithRetry(endpoint: endpoint, retryCount: retryCount)
                }
            }

            var results: [GlobalServerFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private static func fetchWithRetry(endpoint: GlobalStatsServerEndpoint, retryCount: Int) async -> GlobalServerFetchResult {
        for attempt in 0...retryCount {
            do {
                let stats = try await fetch(for: endpoint)
                return GlobalServerFetchResult(serverID: endpoint.id, isOnline: true, stats: stats)
            } catch {
                guard attempt < retryCount else {
                    return GlobalServerFetchResult(serverID: endpoint.id, isOnline: false, stats: nil)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        return GlobalServerFetchResult(serverID: endpoint.id, isOnline: false, stats: nil)
    }

    private static func fetch(for endpoint: GlobalStatsServerEndpoint) async throws -> GlobalStatsServerSnapshot {
        switch endpoint.serverType {
        case .qBittorrent:
            return try await fetchQBittorrentStats(for: endpoint)
        case .transmission:
            return try await fetchTransmissionStats(for: endpoint)
        }
    }

    private static func fetchQBittorrentStats(for endpoint: GlobalStatsServerEndpoint) async throws -> GlobalStatsServerSnapshot {
        let session = makeSession(allowInsecureSSL: endpoint.allowInsecureSSL)
        let baseURL = normalizedBaseURL(address: endpoint.address, port: endpoint.port, useHTTPS: endpoint.useHTTPS)

        let loginSucceeded: Bool
        do {
            try await qbLogin(endpoint: endpoint, baseURL: baseURL, session: session)
            loginSucceeded = true
        } catch {
            loginSucceeded = false
        }

        async let transfer = qbFetchTransferInfo(endpoint: endpoint, baseURL: baseURL, session: session)
        async let mainData = qbFetchMainData(endpoint: endpoint, baseURL: baseURL, session: session)
        async let defaultSavePath = qbFetchDefaultSavePath(endpoint: endpoint, baseURL: baseURL, session: session)

        let torrentItems = (try? await qbFetchTorrents(endpoint: endpoint, baseURL: baseURL, session: session)) ?? []
        let transferInfo = await transfer
        let mainDataInfo = await mainData
        let savePathFromPreferences = await defaultSavePath

        let seedingStates: Set<String> = ["uploading", "stalledUP", "forcedUP", "up"]
        let downloadingStates: Set<String> = ["metaDL", "allocating", "downloading", "dl", "stalledDL", "queuedDL"]

        let seedingCount = torrentItems.filter { seedingStates.contains($0.state) }.count
        let downloadingCount = torrentItems.filter { downloadingStates.contains($0.state) }.count
        let serverState = mainDataInfo?.serverState
        let downloadSpeed = serverState?.dlInfoSpeed ?? transferInfo?.dlInfoSpeed ?? 0
        let uploadSpeed = serverState?.upInfoSpeed ?? transferInfo?.upInfoSpeed ?? 0
        let totalBandwidth = Int64(downloadSpeed) + Int64(uploadSpeed)
        let torrentTotalDownloaded = torrentItems.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.downloaded ?? 0, 0)
        }
        let torrentTotalUploaded = torrentItems.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.uploaded ?? 0, 0)
        }
        let totalAllTimeDownloaded = max(
            serverState?.allTimeDownloaded ?? transferInfo?.allTimeDownloaded ?? torrentTotalDownloaded,
            0
        )
        let totalAllTimeUploaded = max(
            serverState?.allTimeUploaded ?? transferInfo?.allTimeUploaded ?? torrentTotalUploaded,
            0
        )

        let remainingSpace = serverState?.freeSpaceOnDisk ?? transferInfo?.freeSpaceOnDisk ?? 0

        let fallbackPath = serverState?.defaultSavePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPath: String
        if savePathFromPreferences == "--" {
            resolvedPath = fallbackPath.isEmpty ? "--" : fallbackPath
        } else {
            resolvedPath = savePathFromPreferences
        }

        let hasStorageSignal =
            serverState?.freeSpaceOnDisk != nil ||
            transferInfo?.freeSpaceOnDisk != nil ||
            resolvedPath != "--"

        if !loginSucceeded && !hasStorageSignal && torrentItems.isEmpty {
            throw TorrentClientError.authenticationFailed
        }

        return GlobalStatsServerSnapshot(
            seedingCount: seedingCount,
            downloadingCount: downloadingCount,
            totalBandwidth: totalBandwidth,
            remainingSpace: remainingSpace,
            defaultSavePath: resolvedPath,
            totalAllTimeDownloaded: totalAllTimeDownloaded,
            totalAllTimeUploaded: totalAllTimeUploaded
        )
    }

    private static func qbLogin(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async throws {
        guard let url = qbAPIURL(endpoint: endpoint, baseURL: baseURL, path: "auth/login") else {
            throw TorrentClientError.invalidURL
        }

        try await QBittorrentAPI.login(
            session: session, url: url, username: endpoint.username,
            secret: endpoint.password, usesAPIKey: endpoint.qbUsesAPIKey
        )
    }

    private static func qbFetchTorrents(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async throws -> [QBTorrentLite] {
        guard let url = qbAPIURL(endpoint: endpoint, baseURL: baseURL, path: "torrents/info") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = heavyPayloadTimeout
        QBittorrentAPI.configure(&request, apiKey: endpoint.qbUsesAPIKey ? endpoint.password : nil)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("qB torrents/info failed")
        }

        return try JSONDecoder().decode([QBTorrentLite].self, from: data)
    }

    private static func qbFetchTransferInfo(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async -> QBTransferInfoLite? {
        guard let url = qbAPIURL(endpoint: endpoint, baseURL: baseURL, path: "transfer/info") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = standardRequestTimeout
        QBittorrentAPI.configure(&request, apiKey: endpoint.qbUsesAPIKey ? endpoint.password : nil)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return QBTransferInfoLite(
                dlInfoSpeed: intValue(object["dl_info_speed"]),
                upInfoSpeed: intValue(object["up_info_speed"]),
                freeSpaceOnDisk: int64Value(object["free_space_on_disk"]),
                allTimeDownloaded: int64Value(object["alltime_dl"]),
                allTimeUploaded: int64Value(object["alltime_ul"])
            )
        } catch {
            return nil
        }
    }

    private static func qbFetchMainData(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async -> QBMainDataLite? {
        guard let url = qbAPIURL(endpoint: endpoint, baseURL: baseURL, path: "sync/maindata?rid=0") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = heavyPayloadTimeout
        QBittorrentAPI.configure(&request, apiKey: endpoint.qbUsesAPIKey ? endpoint.password : nil)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let serverStateObject = object["server_state"] as? [String: Any]
            else {
                return nil
            }

            let serverState = QBMainDataLite.ServerState(
                freeSpaceOnDisk: int64Value(serverStateObject["free_space_on_disk"]),
                dlInfoSpeed: intValue(serverStateObject["dl_info_speed"]),
                upInfoSpeed: intValue(serverStateObject["up_info_speed"]),
                defaultSavePath: stringValue(serverStateObject["default_save_path"]),
                allTimeDownloaded: int64Value(serverStateObject["alltime_dl"]),
                allTimeUploaded: int64Value(serverStateObject["alltime_ul"])
            )
            return QBMainDataLite(serverState: serverState)
        } catch {
            return nil
        }
    }

    private static func qbFetchDefaultSavePath(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async -> String {
        guard let url = qbAPIURL(endpoint: endpoint, baseURL: baseURL, path: "app/preferences") else {
            return "--"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = standardRequestTimeout
        QBittorrentAPI.configure(&request, apiKey: endpoint.qbUsesAPIKey ? endpoint.password : nil)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return "--"
            }
            let preferences = try JSONDecoder().decode(QBPreferencesLite.self, from: data)
            let path = preferences.savePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? "--" : path
        } catch {
            return "--"
        }
    }

    private static func fetchTransmissionStats(for endpoint: GlobalStatsServerEndpoint) async throws -> GlobalStatsServerSnapshot {
        let session = makeSession(allowInsecureSSL: endpoint.allowInsecureSSL)
        var sessionID: String?

        let torrentData = try await transmissionRPC(
            endpoint: endpoint,
            session: session,
            sessionID: &sessionID,
            method: "torrent-get",
            arguments: ["fields": ["status", "rateDownload", "rateUpload", "downloadedEver", "uploadedEver"]]
        )
        let torrents = try decodeTransmissionRPC(data: torrentData, as: TransmissionTorrentGetLite.self).torrents

        let seedingCount = torrents.filter { $0.status == 5 || $0.status == 6 }.count
        let downloadingCount = torrents.filter { $0.status == 3 || $0.status == 4 }.count
        let totalBandwidth = torrents.reduce(Int64(0)) { $0 + $1.rateDownload + $1.rateUpload }
        let torrentTotalDownloaded = torrents.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.downloadedEver ?? 0, 0)
        }
        let torrentTotalUploaded = torrents.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.uploadedEver ?? 0, 0)
        }

        let sessionData = try await transmissionRPC(
            endpoint: endpoint,
            session: session,
            sessionID: &sessionID,
            method: "session-get",
            arguments: nil
        )
        let sessionInfo = try decodeTransmissionRPC(data: sessionData, as: TransmissionSessionGetLite.self)

        let freeSpaceData = try await transmissionRPC(
            endpoint: endpoint,
            session: session,
            sessionID: &sessionID,
            method: "free-space",
            arguments: ["path": sessionInfo.downloadDir]
        )
        let freeSpace = try decodeTransmissionRPC(data: freeSpaceData, as: TransmissionFreeSpaceLite.self).sizeBytes
        let sessionStatsData = try? await transmissionRPC(
            endpoint: endpoint,
            session: session,
            sessionID: &sessionID,
            method: "session-stats",
            arguments: nil
        )
        let sessionStats = sessionStatsData.flatMap {
            try? decodeTransmissionRPC(data: $0, as: TransmissionSessionStatsLite.self)
        }
        let totalAllTimeDownloaded = max(
            sessionStats?.cumulativeStats.downloadedBytes ?? torrentTotalDownloaded,
            torrentTotalDownloaded
        )
        let totalAllTimeUploaded = max(
            sessionStats?.cumulativeStats.uploadedBytes ?? torrentTotalUploaded,
            torrentTotalUploaded
        )

        return GlobalStatsServerSnapshot(
            seedingCount: seedingCount,
            downloadingCount: downloadingCount,
            totalBandwidth: totalBandwidth,
            remainingSpace: freeSpace,
            defaultSavePath: sessionInfo.downloadDir,
            totalAllTimeDownloaded: totalAllTimeDownloaded,
            totalAllTimeUploaded: totalAllTimeUploaded
        )
    }

    private static func transmissionRPC(
        endpoint: GlobalStatsServerEndpoint,
        session: URLSession,
        sessionID: inout String?,
        method: String,
        arguments: [String: Any]?
    ) async throws -> Data {
        guard let rpcURL = transmissionRPCURL(endpoint: endpoint) else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.timeoutInterval = method == "torrent-get" || method == "session-stats"
            ? heavyPayloadTimeout
            : standardRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeaderValue(username: endpoint.username, password: endpoint.password), forHTTPHeaderField: "Authorization")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
        }

        let body: [String: Any] = [
            "method": method,
            "arguments": arguments ?? [:]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 409,
           let newSessionID = httpResponse.value(forHTTPHeaderField: "X-Transmission-Session-Id") {
            sessionID = newSessionID
            request.setValue(newSessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            (data, response) = try await session.data(for: request)
        }

        guard let finalResponse = response as? HTTPURLResponse, finalResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("Transmission RPC failed: \(method)")
        }

        return data
    }

    private static func decodeTransmissionRPC<T: Decodable>(data: Data, as type: T.Type) throws -> T {
        let envelope = try JSONDecoder().decode(TransmissionEnvelope<T>.self, from: data)
        guard envelope.result == "success", let args = envelope.arguments else {
            throw TorrentClientError.apiError("Transmission RPC result: \(envelope.result)")
        }
        return args
    }

    private static func makeSession(allowInsecureSSL: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = standardRequestTimeout
        config.timeoutIntervalForResource = heavyPayloadTimeout
        let delegate = NetworkManager(allowInsecureSSL: allowInsecureSSL, preservesBearerAuthorization: true)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func normalizedBaseURL(address: String, port: Int, useHTTPS: Bool) -> String {
        let normalized = normalizedHostAndScheme(address: address, useHTTPS: useHTTPS)
        return "\(normalized.scheme)://\(normalized.host):\(port)"
    }

    private static func transmissionRPCURL(endpoint: GlobalStatsServerEndpoint) -> URL? {
        let normalized = normalizedHostAndScheme(address: endpoint.address, useHTTPS: endpoint.useHTTPS)
        let path = endpoint.rpcPath.hasPrefix("/") ? endpoint.rpcPath : "/\(endpoint.rpcPath)"
        return URL(string: "\(normalized.scheme)://\(normalized.host):\(endpoint.port)\(path)")
    }

    private static func qbAPIURL(endpoint: GlobalStatsServerEndpoint, baseURL: String, path: String) -> URL? {
        let trimmed = endpoint.rpcPath.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix: String
        if trimmed.isEmpty {
            prefix = "/api/v2"
        } else {
            let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
            prefix = normalized == "/transmission/rpc" ? "/api/v2" : normalized
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "\(baseURL)\(prefix)\(normalizedPath)")
    }

    private static func normalizedHostAndScheme(address: String, useHTTPS: Bool) -> (host: String, scheme: String) {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmed = raw
        let lower = raw.lowercased()

        let scheme: String
        if lower.hasPrefix("https://") {
            scheme = "https"
            if let url = URL(string: raw), let host = url.host, !host.isEmpty {
                return (host: host, scheme: scheme)
            }
            trimmed = String(raw.dropFirst(8))
        } else if lower.hasPrefix("http://") {
            scheme = "http"
            if let url = URL(string: raw), let host = url.host, !host.isEmpty {
                return (host: host, scheme: scheme)
            }
            trimmed = String(raw.dropFirst(7))
        } else {
            scheme = useHTTPS ? "https" : "http"
        }

        if let slash = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slash])
        }

        if !trimmed.hasPrefix("["),
           let colon = trimmed.lastIndex(of: ":"),
           colon != trimmed.startIndex {
            let hostPart = String(trimmed[..<colon])
            let portPart = String(trimmed[trimmed.index(after: colon)...])
            if Int(portPart) != nil, !hostPart.isEmpty {
                trimmed = hostPart
            }
        }

        return (host: trimmed, scheme: scheme)
    }

    private static func basicAuthHeaderValue(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let int64Value = value as? Int64 { return Int(int64Value) }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let int64Value = value as? Int64 { return int64Value }
        if let intValue = value as? Int { return Int64(intValue) }
        if let doubleValue = value as? Double { return Int64(doubleValue) }
        if let stringValue = value as? String { return Int64(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

private struct QBTorrentLite: Decodable {
    let state: String
    let downloaded: Int64?
    let uploaded: Int64?
}

private struct QBTransferInfoLite: Decodable {
    let dlInfoSpeed: Int?
    let upInfoSpeed: Int?
    let freeSpaceOnDisk: Int64?
    let allTimeDownloaded: Int64?
    let allTimeUploaded: Int64?

    enum CodingKeys: String, CodingKey {
        case dlInfoSpeed = "dl_info_speed"
        case upInfoSpeed = "up_info_speed"
        case freeSpaceOnDisk = "free_space_on_disk"
        case allTimeDownloaded = "alltime_dl"
        case allTimeUploaded = "alltime_ul"
    }
}

private struct QBMainDataLite: Decodable {
    struct ServerState: Decodable {
        let freeSpaceOnDisk: Int64?
        let dlInfoSpeed: Int?
        let upInfoSpeed: Int?
        let defaultSavePath: String?
        let allTimeDownloaded: Int64?
        let allTimeUploaded: Int64?

        enum CodingKeys: String, CodingKey {
            case freeSpaceOnDisk = "free_space_on_disk"
            case dlInfoSpeed = "dl_info_speed"
            case upInfoSpeed = "up_info_speed"
            case defaultSavePath = "default_save_path"
            case allTimeDownloaded = "alltime_dl"
            case allTimeUploaded = "alltime_ul"
        }
    }

    let serverState: ServerState?

    enum CodingKeys: String, CodingKey {
        case serverState = "server_state"
    }
}

private struct QBPreferencesLite: Decodable {
    let savePath: String?

    enum CodingKeys: String, CodingKey {
        case savePath = "save_path"
    }
}

private struct TransmissionEnvelope<T: Decodable>: Decodable {
    let result: String
    let arguments: T?
}

private struct TransmissionTorrentGetLite: Decodable {
    struct Item: Decodable {
        let status: Int
        let rateDownload: Int64
        let rateUpload: Int64
        let downloadedEver: Int64?
        let uploadedEver: Int64?

        enum CodingKeys: String, CodingKey {
            case status
            case rateDownload
            case rateUpload
            case downloadedEver
            case uploadedEver
        }
    }

    let torrents: [Item]
}

private struct TransmissionSessionGetLite: Decodable {
    let downloadDir: String

    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
    }
}

private struct TransmissionFreeSpaceLite: Decodable {
    let sizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case sizeBytes = "size-bytes"
    }
}

private struct TransmissionSessionStatsLite: Decodable {
    struct CumulativeStats: Decodable {
        let downloadedBytes: Int64
        let uploadedBytes: Int64
    }

    let cumulativeStats: CumulativeStats

    enum CodingKeys: String, CodingKey {
        case cumulativeStats = "cumulative-stats"
    }
}
