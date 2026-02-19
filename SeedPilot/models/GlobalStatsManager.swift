//
//  GlobalStatsManager.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Observation

struct DashboardServerStorageEntry: Identifiable, Hashable {
    let id: UUID
    let serverName: String
    let defaultSavePath: String
    let remainingSpace: Int64?
    let isOnline: Bool
    let statusMessage: String
}

struct GlobalStatsSnapshot {
    var totalSeedingCount: Int = 0
    var totalDownloadingCount: Int = 0
    var totalBandwidth: Int64 = 0
    var totalRemainingSpace: Int64 = 0
    var onlineServerCount: Int = 0
    var failedServerCount: Int = 0
    var hasConnectionIssue: Bool = false
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
    private var lastKnownStatusByServer: [UUID: Bool] = [:]
    private var failureStreakByServer: [UUID: Int] = [:]
    private var lastKnownStatsByServer: [UUID: GlobalStatsServerSnapshot] = [:]

    private init() {}

    func refresh(servers: [ServerConfig], force: Bool = false) async {
        let validServerIDs = Set(servers.map(\.id))
        lastKnownStatusByServer = lastKnownStatusByServer.filter { validServerIDs.contains($0.key) }
        failureStreakByServer = failureStreakByServer.filter { validServerIDs.contains($0.key) }
        lastKnownStatsByServer = lastKnownStatsByServer.filter { validServerIDs.contains($0.key) }

        let signature = serverSignature(servers)

        if !force, shouldUseCache(signature: signature) {
            syncCachedConnectionState(from: servers)
            return
        }

        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
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
            lastKnownStatusByServer.removeAll()
            failureStreakByServer.removeAll()
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
        guard let lastFetchedAt else { return false }
        let age = Date().timeIntervalSince(lastFetchedAt)
        return age < cacheTTL && signature == lastServerSignature
    }

    private func syncCachedConnectionState(from servers: [ServerConfig]) {
        let onlineMap = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0.isOnline == true) })
        for server in servers {
            lastKnownStatusByServer[server.id] = server.isOnline == true
        }

        snapshot.serverStorage = snapshot.serverStorage.map { entry in
            let isOnline = onlineMap[entry.id] ?? lastKnownStatusByServer[entry.id] ?? entry.isOnline
            return DashboardServerStorageEntry(
                id: entry.id,
                serverName: entry.serverName,
                defaultSavePath: entry.defaultSavePath,
                remainingSpace: entry.remainingSpace,
                isOnline: isOnline,
                statusMessage: isOnline ? "在线" : "连接异常"
            )
        }

        snapshot.onlineServerCount = servers.filter { $0.isOnline == true }.count
        snapshot.failedServerCount = servers.count - snapshot.onlineServerCount
        snapshot.hasConnectionIssue = !servers.isEmpty && snapshot.onlineServerCount == 0
    }

    private func applyConnectionState(to servers: [ServerConfig], results: [GlobalServerFetchResult]) {
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.serverID, $0) })

        for server in servers {
            guard let result = resultMap[server.id] else {
                let streak = (failureStreakByServer[server.id] ?? 0) + 1
                failureStreakByServer[server.id] = streak
                let keepOnline = (lastKnownStatusByServer[server.id] == true) && streak <= 1
                server.isOnline = keepOnline
                if !keepOnline {
                    lastKnownStatusByServer[server.id] = false
                }
                continue
            }

            if result.isOnline {
                failureStreakByServer[server.id] = 0
                lastKnownStatusByServer[server.id] = true
                server.isOnline = true
            } else {
                let streak = (failureStreakByServer[server.id] ?? 0) + 1
                failureStreakByServer[server.id] = streak
                let keepOnline = (lastKnownStatusByServer[server.id] == true) && streak <= 1
                server.isOnline = keepOnline
                if !keepOnline {
                    lastKnownStatusByServer[server.id] = false
                }
            }
        }
    }

    private func buildSnapshot(servers: [ServerConfig], results: [GlobalServerFetchResult]) -> GlobalStatsSnapshot {
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.serverID, $0) })

        var totalSeedingCount = 0
        var totalDownloadingCount = 0
        var totalBandwidth: Int64 = 0
        var totalRemainingSpace: Int64 = 0
        var onlineServerCount = 0
        var failedServerCount = 0

        var storageRows: [DashboardServerStorageEntry] = []
        storageRows.reserveCapacity(servers.count)

        for server in servers {
            let result = resultMap[server.id]
            if let freshStats = result?.stats {
                lastKnownStatsByServer[server.id] = freshStats
            }

            let isOnline = server.isOnline == true
            let effectiveStats = result?.stats ?? (isOnline ? lastKnownStatsByServer[server.id] : nil)

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
                        isOnline: true,
                        statusMessage: "在线"
                    )
                )
            } else {
                failedServerCount += 1
                storageRows.append(
                    DashboardServerStorageEntry(
                        id: server.id,
                        serverName: server.name,
                        defaultSavePath: effectiveStats?.defaultSavePath ?? "--",
                        remainingSpace: nil,
                        isOnline: false,
                        statusMessage: "连接异常"
                    )
                )
            }
        }

        return GlobalStatsSnapshot(
            totalSeedingCount: totalSeedingCount,
            totalDownloadingCount: totalDownloadingCount,
            totalBandwidth: totalBandwidth,
            totalRemainingSpace: totalRemainingSpace,
            onlineServerCount: onlineServerCount,
            failedServerCount: failedServerCount,
            hasConnectionIssue: onlineServerCount == 0,
            serverStorage: storageRows,
            lastUpdatedAt: Date()
        )
    }

    private func serverSignature(_ servers: [ServerConfig]) -> String {
        servers
            .map {
                "\($0.id.uuidString)|\($0.type.rawValue)|\($0.address)|\($0.port)|\($0.username)|\($0.useHTTPS)|\($0.rpcPath)|\($0.allowInsecureSSL)"
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
        self.password = server.password
        self.useHTTPS = server.useHTTPS
        self.allowInsecureSSL = server.allowInsecureSSL
        self.rpcPath = server.rpcPath
    }
}

private enum GlobalStatsFetcher {
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

        try await qbLogin(endpoint: endpoint, baseURL: baseURL, session: session)

        async let torrents = qbFetchTorrents(baseURL: baseURL, session: session)
        async let transfer = qbFetchTransferInfo(baseURL: baseURL, session: session)
        async let defaultSavePath = qbFetchDefaultSavePath(baseURL: baseURL, session: session)

        let torrentItems = try await torrents
        let transferInfo = try await transfer

        let seedingStates: Set<String> = ["uploading", "stalledUP", "forcedUP", "up"]
        let downloadingStates: Set<String> = ["metaDL", "allocating", "downloading", "dl", "stalledDL", "queuedDL"]

        let seedingCount = torrentItems.filter { seedingStates.contains($0.state) }.count
        let downloadingCount = torrentItems.filter { downloadingStates.contains($0.state) }.count
        let totalBandwidth = Int64(transferInfo.dlInfoSpeed) + Int64(transferInfo.upInfoSpeed)

        return GlobalStatsServerSnapshot(
            seedingCount: seedingCount,
            downloadingCount: downloadingCount,
            totalBandwidth: totalBandwidth,
            remainingSpace: transferInfo.freeSpaceOnDisk,
            defaultSavePath: await defaultSavePath
        )
    }

    private static func qbLogin(endpoint: GlobalStatsServerEndpoint, baseURL: String, session: URLSession) async throws {
        guard let url = URL(string: "\(baseURL)/api/v2/auth/login") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")

        let encodedUsername = endpoint.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? endpoint.username
        let encodedPassword = endpoint.password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? endpoint.password
        request.httpBody = "username=\(encodedUsername)&password=\(encodedPassword)".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.authenticationFailed
        }

        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard body == "Ok." else {
            throw TorrentClientError.authenticationFailed
        }
    }

    private static func qbFetchTorrents(baseURL: String, session: URLSession) async throws -> [QBTorrentLite] {
        guard let url = URL(string: "\(baseURL)/api/v2/torrents/info") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("qB torrents/info failed")
        }

        return try JSONDecoder().decode([QBTorrentLite].self, from: data)
    }

    private static func qbFetchTransferInfo(baseURL: String, session: URLSession) async throws -> QBTransferInfoLite {
        guard let url = URL(string: "\(baseURL)/api/v2/transfer/info") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("qB transfer/info failed")
        }

        return try JSONDecoder().decode(QBTransferInfoLite.self, from: data)
    }

    private static func qbFetchDefaultSavePath(baseURL: String, session: URLSession) async -> String {
        guard let url = URL(string: "\(baseURL)/api/v2/app/preferences") else {
            return "--"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

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
            arguments: ["fields": ["status", "rateDownload", "rateUpload"]]
        )
        let torrents = try decodeTransmissionRPC(data: torrentData, as: TransmissionTorrentGetLite.self).torrents

        let seedingCount = torrents.filter { $0.status == 5 || $0.status == 6 }.count
        let downloadingCount = torrents.filter { $0.status == 3 || $0.status == 4 }.count
        let totalBandwidth = torrents.reduce(Int64(0)) { $0 + $1.rateDownload + $1.rateUpload }

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

        return GlobalStatsServerSnapshot(
            seedingCount: seedingCount,
            downloadingCount: downloadingCount,
            totalBandwidth: totalBandwidth,
            remainingSpace: freeSpace,
            defaultSavePath: sessionInfo.downloadDir
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
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage()
        config.httpCookieAcceptPolicy = .always
        let delegate = NetworkManager(allowInsecureSSL: allowInsecureSSL)
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
}

private struct QBTorrentLite: Decodable {
    let state: String
}

private struct QBTransferInfoLite: Decodable {
    let dlInfoSpeed: Int
    let upInfoSpeed: Int
    let freeSpaceOnDisk: Int64

    enum CodingKeys: String, CodingKey {
        case dlInfoSpeed = "dl_info_speed"
        case upInfoSpeed = "up_info_speed"
        case freeSpaceOnDisk = "free_space_on_disk"
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
