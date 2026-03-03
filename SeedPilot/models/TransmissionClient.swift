//
//  TransmissionClient.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation

class TransmissionClient: NSObject, TorrentClient {
    private let config: ServerConfig
    private var sessionID: String?

    private lazy var session: URLSession = {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieStorage = HTTPCookieStorage.shared
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.waitsForConnectivity = false
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.timeoutIntervalForResource = 20
        let delegate = NetworkManager(allowInsecureSSL: config.allowInsecureSSL)
        return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }()

    init(config: ServerConfig) {
        self.config = config
        super.init()
    }

    private func getRPCURL() -> URL? {
        let path = config.rpcPath.hasPrefix("/") ? config.rpcPath : "/\(config.rpcPath)"
        return URL(string: "\(config.baseURL)\(path)")
    }

    private func configureRequest(_ request: inout URLRequest) {
        let authString = "\(config.username):\(config.resolvedPassword)"
        if let authData = authString.data(using: .utf8) {
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        }
        if let sid = sessionID {
            request.setValue(sid, forHTTPHeaderField: "X-Transmission-Session-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
    }

    private func prefetchSessionID(url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5 // Short timeout — this is just an optimization
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["method": "session-get", "arguments": [:] as [String: Any]])
        configureRequest(&request)
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              let sid = http.value(forHTTPHeaderField: "X-Transmission-Session-Id") else { return }
        self.sessionID = sid
    }

    private func performRequest<T: Decodable>(_ method: String, arguments: [String: Any]?, responseType: T.Type) async throws -> T {
        guard let url = getRPCURL() else { throw TorrentClientError.invalidURL }

        // Pre-fetch session ID on cold start to avoid 409 storm
        if sessionID == nil {
            await prefetchSessionID(url: url)
        }

        for attempt in 0..<2 {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let body: [String: Any] = [
                    "method": method,
                    "arguments": arguments ?? [:]
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                configureRequest(&request)

                var (data, response) = try await session.data(for: request)

                // Handle CSRF 409
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 409 {
                    if let newSID = httpResponse.value(forHTTPHeaderField: "X-Transmission-Session-Id") {
                        self.sessionID = newSID
                        // Retry once with new session id
                        configureRequest(&request)
                        (data, response) = try await session.data(for: request)
                    } else {
                        throw TorrentClientError.apiError("Transmission: 409 Conflict but no Session ID returned")
                    }
                }

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw TorrentClientError.apiError("Transmission API Error: \(response)")
                }

                let rpcResponse = try await decodeOnBackground(TransmissionRPCResponse<T>.self, from: data)

                if rpcResponse.result != "success" {
                    throw TorrentClientError.apiError("Transmission RPC Error: \(rpcResponse.result)")
                }

                guard let args = rpcResponse.arguments else {
                    throw TorrentClientError.apiError("Transmission RPC: No arguments in response")
                }

                return args
            } catch {
                if attempt == 0, shouldRetryTransientNetworkError(error) {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                throw error
            }
        }

        throw TorrentClientError.apiError("Transmission request retry exhausted")
    }

    private func shouldRetryTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    // MARK: - Protocol Implementation

    func login() async throws {
        // Transmission uses Basic Auth per request, so login is just ensuring we have a session ID
        // We can do a lightweight call
        _ = try await checkConnection()
    }

    func checkConnection() async throws -> String {
        struct SessionGet: Decodable {
            let version: String
        }
        let args = try await performRequest("session-get", arguments: nil, responseType: SessionGet.self)
        return args.version
    }

    func fetchTorrents() async throws -> [TorrentTask] {
        struct TorrentGet: Decodable {
            struct Item: Decodable {
                struct Tracker: Decodable {
                    let announce: String?
                }

                let id: Int
                let hashString: String
                let name: String
                let totalSize: Int64
                let rateDownload: Int64
                let rateUpload: Int64
                let status: Int
                let error: Int?
                let errorString: String?
                let downloadDir: String
                let percentDone: Double
                let doneDate: Int?
                let eta: Int
                let downloadedEver: Int64
                let uploadedEver: Int64
                let uploadRatio: Double
                let peersConnected: Int
                let addedDate: Int?
                let secondsSeeding: Int? // Optional
                let tracker: String?
                let trackers: [Tracker]?
                let labels: [String]?
            }
            let torrents: [Item]
        }

        let fields = [
            "id", "hashString", "name", "totalSize", "rateDownload", "rateUpload",
            "status", "error", "errorString", "downloadDir", "percentDone", "doneDate", "eta", "downloadedEver",
            "uploadedEver", "uploadRatio", "peersConnected", "addedDate", "secondsSeeding",
            "tracker", "trackers", "labels"
        ]

        let args = try await performRequest("torrent-get", arguments: ["fields": fields], responseType: TorrentGet.self)
        let serverID = config.id

        func normalizedTrackerURL(_ raw: String) -> String {
            if URL(string: raw) != nil {
                return raw
            }
            // Some clients may return host/path without scheme. Add a scheme so existing URL-host formatting works.
            return "http://\(raw)"
        }

        func pickTrackerURL(primary: String?, trackers: [TorrentGet.Item.Tracker]?) -> String {
            let primaryCandidate = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !primaryCandidate.isEmpty {
                return normalizedTrackerURL(primaryCandidate)
            }

            if let firstAnnounce = trackers?
                .compactMap(\.announce)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return normalizedTrackerURL(firstAnnounce)
            }

            return ""
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                func normalizeLabels(_ labels: [String]) -> [String] {
                    Array(
                        Set(
                            labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        )
                    )
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }

                let mapped = args.torrents.map { item in
                    let trackerURL = pickTrackerURL(primary: item.tracker, trackers: item.trackers)
                    let progress = (item.percentDone * 1000).rounded() / 1000   // 0.1% granularity
                    let size = item.totalSize
                    let downloadSpeed = (item.rateDownload / 1024) * 1024        // 1 KB granularity
                    let uploadSpeed = (item.rateUpload / 1024) * 1024            // 1 KB granularity
                    let seedingTime = TimeInterval(item.secondsSeeding ?? 0)
                    let numSeeds = 0
                    let totalSeeds = 0
                    let numPeers = item.peersConnected
                    let totalPeers = 0
                    let ratio = item.uploadRatio

                    let displayText = TorrentTaskDisplayText.build(
                        title: item.name,
                        progress: progress,
                        seedingTime: seedingTime,
                        downloadSpeed: downloadSpeed,
                        uploadSpeed: uploadSpeed,
                        numPeers: numPeers,
                        totalPeers: totalPeers,
                        numSeeds: numSeeds,
                        totalSeeds: totalSeeds,
                        size: size,
                        ratio: ratio
                    )

                    return TorrentTask(
                        hash: item.hashString,
                        name: item.name,
                        progress: progress,
                        size: size,
                        downloadSpeed: downloadSpeed,
                        uploadSpeed: uploadSpeed,
                        remainingTime: TimeInterval(item.eta),
                        status: Self.mapTransmissionStatus(
                            item.status,
                            errorCode: item.error,
                            errorMessage: item.errorString
                        ),
                        errorCode: item.error,
                        errorMessage: item.errorString,
                        serverID: serverID,
                        tracker: trackerURL,
                        savePath: item.downloadDir,
                        category: "",
                        tags: normalizeLabels(item.labels ?? []).joined(separator: ","),
                        downloaded: item.downloadedEver,
                        uploaded: item.uploadedEver,
                        isSequential: nil,
                        isFirstLastPiecePriority: nil,
                        completionDate: item.doneDate.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                        seedingTime: seedingTime,
                        addedTime: item.addedDate.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast,
                        resolutionBadge: ResolutionExtractor.extractBadge(from: item.name),
                        displayText: displayText,
                        numSeeds: numSeeds,
                        totalSeeds: totalSeeds,
                        numPeers: numPeers,
                        totalPeers: totalPeers,
                        ratio: ratio
                    )
                }

                continuation.resume(returning: mapped)
            }
        }
    }

    func addTorrents(_ urls: [String], options: AddTorrentOptions) async throws {
        for url in urls {
            var args: [String: Any] = [
                "filename": url,
                "paused": options.isPaused
            ]
            if !options.savePath.isEmpty {
                args["download-dir"] = options.savePath
            }
            if !options.tags.isEmpty {
                args["labels"] = normalizeTags(options.tags)
            }

           struct AddResponse: Decodable {} // We don't need content, just success result
           _ = try await performRequest("torrent-add", arguments: args, responseType: AddResponse.self)
        }
    }

    func addTorrentFile(_ fileURL: URL, options: AddTorrentOptions) async throws {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw TorrentClientError.apiError("Cannot read file")
        }
        let base64 = data.base64EncodedString()

        var args: [String: Any] = [
            "metainfo": base64,
            "paused": options.isPaused
        ]
        if !options.savePath.isEmpty {
            args["download-dir"] = options.savePath
        }
        if !options.tags.isEmpty {
            args["labels"] = normalizeTags(options.tags)
        }

        struct AddResponse: Decodable {}
        _ = try await performRequest("torrent-add", arguments: args, responseType: AddResponse.self)
    }

    // MARK: - Actions

    func pauseTask(hash: String) async throws {
        _ = try await performRequest("torrent-stop", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
    }

    func resumeTask(hash: String) async throws {
        _ = try await performRequest("torrent-start", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
    }

    func deleteTask(hash: String, withData: Bool) async throws {
        _ = try await performRequest("torrent-remove", arguments: ["ids": [hash], "delete-local-data": withData], responseType: EmptyArgs.self)
    }

    // MARK: - Stubs for unused/advanced methods (Transmission implementation pending)

    func recheckTask(hash: String) async throws {
        _ = try await performRequest("torrent-verify", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
    }

    func reannounceTask(hash: String) async throws {
         _ = try await performRequest("torrent-reannounce", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
    }

    // Transmission RPC doesn't support sequential/priority toggle easily per file via simple main RPC
    func toggleSequentialDownload(hash: String) async throws {}
    func toggleFirstLastPiecePriority(hash: String) async throws {}

    func renameTask(hash: String, newName: String) async throws {
         // Transmission rename is 'torrent-rename-path', needs path + name. Complex.
    }

    func forceStartTask(hash: String) async throws {
        do {
            _ = try await performRequest("torrent-start-now", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
        } catch {
            // Compatibility fallback for Transmission variants that don't expose "start-now".
            _ = try await performRequest("torrent-start", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
        }
    }

    func setLocation(hash: String, newLocation: String) async throws {
         _ = try await performRequest("torrent-set-location", arguments: ["ids": [hash], "location": newLocation, "move": true], responseType: EmptyArgs.self)
    }

    func editTrackers(hash: String, newTrackers: String) async throws {
        let trackerURLs = normalizedTrackerURLs(from: newTrackers)
        guard !trackerURLs.isEmpty else {
            throw TorrentClientError.apiError("No valid tracker URL provided")
        }

        struct TrackerGet: Decodable {
            struct Item: Decodable {
                struct Tracker: Decodable {
                    let id: Int
                }
                let trackers: [Tracker]?
            }
            let torrents: [Item]
        }

        let trackerGet = try await performRequest(
            "torrent-get",
            arguments: ["ids": [hash], "fields": ["trackers"]],
            responseType: TrackerGet.self
        )

        let existingTrackerIDs = trackerGet.torrents.first?.trackers?.map(\.id) ?? []

        var setArguments: [String: Any] = [
            "ids": [hash],
            "trackerAdd": trackerURLs
        ]
        if !existingTrackerIDs.isEmpty {
            setArguments["trackerRemove"] = existingTrackerIDs
        }

        _ = try await performRequest("torrent-set", arguments: setArguments, responseType: EmptyArgs.self)
    }

    func fetchTrackers(hash: String) async throws -> [TorrentTrackerInfo] {
        struct TrackerGet: Decodable {
            struct Item: Decodable {
                struct Tracker: Decodable {
                    let id: Int?
                    let announce: String?
                }

                struct TrackerStat: Decodable {
                    let id: Int?
                    let host: String?
                    let announce: String?
                    let seederCount: Int?
                    let leecherCount: Int?
                    let downloadCount: Int?
                    let lastAnnouncePeerCount: Int?
                    let announceState: Int?
                    let scrapeState: Int?
                    let hasAnnounced: Bool?
                    let hasScraped: Bool?
                    let lastAnnounceSucceeded: Bool?
                    let lastScrapeSucceeded: Bool?
                    let lastAnnounceTimedOut: Bool?
                    let lastAnnounceResult: String?
                    let lastScrapeResult: String?
                }

                let trackers: [Tracker]?
                let trackerStats: [TrackerStat]?
            }

            let torrents: [Item]
        }

        func normalizeMessage(_ raw: String?) -> String? {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        func normalizeURL(_ raw: String?) -> String {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "--" : trimmed
        }

        let args = try await performRequest(
            "torrent-get",
            arguments: [
                "ids": [hash],
                "fields": ["trackers", "trackerStats"]
            ],
            responseType: TrackerGet.self
        )

        guard let item = args.torrents.first else { return [] }

        var trackerURLByID: [Int: String] = [:]
        if let trackers = item.trackers {
            trackerURLByID.reserveCapacity(max(trackers.count, 1))
            for tracker in trackers {
                guard let id = tracker.id else { continue }
                let url = normalizeURL(tracker.announce)
                if trackerURLByID[id] == nil {
                    trackerURLByID[id] = url
                }
            }
        }

        var output: [TorrentTrackerInfo] = []
        let trackerStats = item.trackerStats ?? []
        output.reserveCapacity(max(trackerStats.count, trackerURLByID.count))

        for (index, stat) in trackerStats.enumerated() {
            let announceMessage = normalizeMessage(stat.lastAnnounceResult)
            let scrapeMessage = normalizeMessage(stat.lastScrapeResult)
            let announceError = announceMessage.map {
                $0.localizedCaseInsensitiveCompare("success") != .orderedSame
            } ?? false
            let scrapeError = scrapeMessage.map {
                $0.localizedCaseInsensitiveCompare("success") != .orderedSame
            } ?? false

            let announceState = stat.announceState ?? 0
            let scrapeState = stat.scrapeState ?? 0
            // Transmission tracker state: waiting/queued is common idle state.
            // Treat only active in-flight announce/scrape as "Updating".
            let isUpdating = announceState == 3 || scrapeState == 3
            let hasSuccessHistory = stat.lastAnnounceSucceeded == true || stat.lastScrapeSucceeded == true
            let hasAnyStats = max(
                stat.lastAnnouncePeerCount ?? 0,
                stat.seederCount ?? 0,
                stat.leecherCount ?? 0,
                stat.downloadCount ?? 0
            ) > 0
            let hasFailureSignal = stat.lastAnnounceTimedOut == true || announceError || scrapeError

            let status: TorrentTrackerStatus = {
                // Prioritize runtime state and known-good stats over stale textual messages.
                if hasSuccessHistory || hasAnyStats { return .working }
                if isUpdating { return .updating }
                if stat.hasAnnounced == false && stat.hasScraped == false { return .notContacted }
                if hasFailureSignal { return .failed }
                return .unknown
            }()

            let message: String? = {
                guard status == .failed else { return nil }
                if announceError, let announceMessage { return announceMessage }
                if scrapeError, let scrapeMessage { return scrapeMessage }
                if stat.lastAnnounceTimedOut == true { return LanguageManager.shared.localized("Timed out") }
                return nil
            }()

            let statID = stat.id ?? -1
            let displayURL = trackerURLByID[statID] ?? normalizeURL(stat.announce ?? stat.host)

            output.append(
                TorrentTrackerInfo(
                    id: "\(statID)|\(displayURL)|\(index)",
                    tier: nil,
                    url: displayURL,
                    status: status,
                    peers: stat.lastAnnouncePeerCount,
                    seeds: stat.seederCount,
                    leeches: stat.leecherCount,
                    downloaded: stat.downloadCount,
                    message: message
                )
            )
        }

        if output.isEmpty && !trackerURLByID.isEmpty {
            let fallbackTrackers = trackerURLByID
                .sorted { $0.key < $1.key }
            output.reserveCapacity(fallbackTrackers.count)
            for (id, url) in fallbackTrackers {
                output.append(
                    TorrentTrackerInfo(
                        id: "\(id)|\(url)",
                        tier: nil,
                        url: url,
                        status: .unknown,
                        peers: nil,
                        seeds: nil,
                        leeches: nil,
                        downloaded: nil,
                        message: nil
                    )
                )
            }
        }

        return output
    }

    // MARK: - File Management

    func getFiles(hash: String) async throws -> [TorrentFile] {
        struct FileGet: Decodable {
            struct Item: Decodable {
                struct FileEntry: Decodable {
                    let name: String
                    let length: Int64
                    let bytesCompleted: Int64
                }
                struct FileStat: Decodable {
                    let wanted: Bool
                    let priority: Int // -1 = low, 0 = normal, 1 = high
                }
                let files: [FileEntry]?
                let fileStats: [FileStat]?
            }
            let torrents: [Item]
        }

        let args = try await performRequest(
            "torrent-get",
            arguments: [
                "ids": [hash],
                "fields": ["files", "fileStats"]
            ],
            responseType: FileGet.self
        )

        guard let torrent = args.torrents.first,
              let files = torrent.files else {
            return []
        }

        let stats = torrent.fileStats ?? []

        return files.enumerated().map { index, file in
            let progress = file.length > 0 ? Double(file.bytesCompleted) / Double(file.length) : 0
            let priority: FilePriority
            if index < stats.count {
                if !stats[index].wanted {
                    priority = .doNotDownload
                } else {
                    switch stats[index].priority {
                    case 1:  priority = .high
                    case -1: priority = .normal
                    default: priority = .normal
                    }
                }
            } else {
                priority = .normal
            }
            return TorrentFile(
                index: index,
                name: file.name,
                size: file.length,
                downloaded: file.bytesCompleted,
                progress: progress,
                priority: priority
            )
        }
    }

    func setFilePriority(hash: String, fileIndices: [Int], priority: FilePriority) async throws {
        var setArgs: [String: Any] = ["ids": [hash]]

        switch priority {
        case .doNotDownload:
            setArgs["files-unwanted"] = fileIndices
        case .normal:
            setArgs["files-wanted"] = fileIndices
            setArgs["priority-normal"] = fileIndices
        case .high:
            setArgs["files-wanted"] = fileIndices
            setArgs["priority-high"] = fileIndices
        case .maximum:
            setArgs["files-wanted"] = fileIndices
            setArgs["priority-high"] = fileIndices
        }

        _ = try await performRequest("torrent-set", arguments: setArgs, responseType: EmptyArgs.self)
    }

    // MARK: - Helpers

    private func mapStatus(_ status: Int, errorCode: Int? = nil, errorMessage: String? = nil) -> TorrentStatus {
        Self.mapTransmissionStatus(status, errorCode: errorCode, errorMessage: errorMessage)
    }

    private static func mapTransmissionStatus(
        _ status: Int,
        errorCode: Int? = nil,
        errorMessage: String? = nil
    ) -> TorrentStatus {
        let hasRPCError = (errorCode ?? 0) != 0 ||
            !(errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if hasRPCError {
            return .error
        }

        // Transmission Status:
        // 0: Stopped, 1: Check Wait, 2: Check, 3: Download Wait, 4: Download, 5: Seed Wait, 6: Seed
        switch status {
        case 0: return .paused
        case 1, 2: return .checking
        case 3, 5: return .queued
        case 4: return .downloading
        case 6: return .seeding
        default: return .error
        }
    }

    private func normalizedTrackerURLs(from raw: String) -> [String] {
        let normalizedSeparators = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let chunks = normalizedSeparators.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })

        var seen = Set<String>()
        var result: [String] = []
        for chunk in chunks {
            let candidate = String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            guard isLikelyTrackerURL(candidate) else { continue }
            let key = candidate.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    private func isLikelyTrackerURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return false
        }

        return ["http", "https", "udp", "ws", "wss"].contains(scheme)
    }

    private func decodeOnBackground<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try JSONDecoder().decode(T.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Connection Settings

    func getConnectionSettings() async throws -> ConnectionSettings {
        struct SessionConnectionGet: Decodable {
            let peerPort: Int
            let portForwardingEnabled: Bool
            let peerLimitGlobal: Int
            let peerLimitPerTorrent: Int
            let utpEnabled: Bool
            let downloadQueueEnabled: Bool
            let downloadQueueSize: Int
            let seedQueueEnabled: Bool
            let seedQueueSize: Int
            let queueStalledEnabled: Bool
            let queueStalledMinutes: Int

            enum CodingKeys: String, CodingKey {
                case peerPort = "peer-port"
                case portForwardingEnabled = "port-forwarding-enabled"
                case peerLimitGlobal = "peer-limit-global"
                case peerLimitPerTorrent = "peer-limit-per-torrent"
                case utpEnabled = "utp-enabled"
                case downloadQueueEnabled = "download-queue-enabled"
                case downloadQueueSize = "download-queue-size"
                case seedQueueEnabled = "seed-queue-enabled"
                case seedQueueSize = "seed-queue-size"
                case queueStalledEnabled = "queue-stalled-enabled"
                case queueStalledMinutes = "queue-stalled-minutes"
            }
        }

        let args = try await performRequest(
            "session-get",
            arguments: nil,
            responseType: SessionConnectionGet.self
        )

        return ConnectionSettings(
            listenPort: max(args.peerPort, 0),
            useUPnP: args.portForwardingEnabled,
            maxConnections: max(args.peerLimitGlobal, 0),
            maxConnectionsPerTorrent: max(args.peerLimitPerTorrent, 0),
            maxUploads: nil,
            maxUploadsPerTorrent: nil,
            bittorrentProtocol: args.utpEnabled ? 0 : 1,
            downloadQueueEnabled: args.downloadQueueEnabled,
            downloadQueueSize: max(args.downloadQueueSize, 0),
            seedQueueEnabled: args.seedQueueEnabled,
            seedQueueSize: max(args.seedQueueSize, 0),
            queueStalledEnabled: args.queueStalledEnabled,
            queueStalledMinutes: max(args.queueStalledMinutes, 0)
        )
    }

    func setConnectionSettings(_ settings: ConnectionSettings) async throws {
        let normalizedPort = min(max(settings.listenPort, 1), 65535)
        let utpEnabled = settings.bittorrentProtocol != 1

        let args: [String: Any] = [
            "peer-port": normalizedPort,
            "port-forwarding-enabled": settings.useUPnP,
            "peer-limit-global": max(settings.maxConnections, 0),
            "peer-limit-per-torrent": max(settings.maxConnectionsPerTorrent, 0),
            "utp-enabled": utpEnabled,
            "download-queue-enabled": settings.downloadQueueEnabled ?? false,
            "download-queue-size": max(settings.downloadQueueSize ?? 0, 0),
            "seed-queue-enabled": settings.seedQueueEnabled ?? false,
            "seed-queue-size": max(settings.seedQueueSize ?? 0, 0),
            "queue-stalled-enabled": settings.queueStalledEnabled ?? false,
            "queue-stalled-minutes": max(settings.queueStalledMinutes ?? 0, 0)
        ]

        _ = try await performRequest("session-set", arguments: args, responseType: EmptyArgs.self)
    }

    func getDownloadSettings() async throws -> DownloadSettings {
        struct SessionDownloadGet: Decodable {
            let downloadDir: String
            let renamePartialFiles: Bool
            let incompleteDirEnabled: Bool
            let incompleteDir: String
            let cacheSizeMB: Int

            enum CodingKeys: String, CodingKey {
                case downloadDir = "download-dir"
                case renamePartialFiles = "rename-partial-files"
                case incompleteDirEnabled = "incomplete-dir-enabled"
                case incompleteDir = "incomplete-dir"
                case cacheSizeMB = "cache-size-mb"
            }
        }

        let args = try await performRequest(
            "session-get",
            arguments: nil,
            responseType: SessionDownloadGet.self
        )

        return DownloadSettings(
            savePath: args.downloadDir,
            appendExtension: args.renamePartialFiles,
            useTempPath: args.incompleteDirEnabled,
            tempPath: args.incompleteDir,
            preallocateAll: nil,
            cacheSizeMB: max(args.cacheSizeMB, 0)
        )
    }

    func setDownloadSettings(_ settings: DownloadSettings) async throws {
        var args: [String: Any] = [
            "download-dir": settings.savePath,
            "rename-partial-files": settings.appendExtension,
            "incomplete-dir-enabled": settings.useTempPath,
            "incomplete-dir": settings.tempPath
        ]
        if let cacheSizeMB = settings.cacheSizeMB {
            args["cache-size-mb"] = max(cacheSizeMB, 0)
        }

        _ = try await performRequest("session-set", arguments: args, responseType: EmptyArgs.self)
    }

    // MARK: - Per-Torrent Speed Limits

    /// Fetch current per-torrent speed limits (KB/s). Returns limits and whether they are enabled.
    func fetchTorrentSpeedLimits(hash: String) async throws -> (dlLimit: Int, dlLimited: Bool, upLimit: Int, upLimited: Bool) {
        struct SpeedLimitGet: Decodable {
            struct Item: Decodable {
                let downloadLimit: Int
                let downloadLimited: Bool
                let uploadLimit: Int
                let uploadLimited: Bool
            }
            let torrents: [Item]
        }

        let args = try await performRequest(
            "torrent-get",
            arguments: [
                "ids": [hash],
                "fields": ["downloadLimit", "downloadLimited", "uploadLimit", "uploadLimited"]
            ],
            responseType: SpeedLimitGet.self
        )

        guard let torrent = args.torrents.first else {
            throw TorrentClientError.apiError("Torrent not found")
        }

        return (
            dlLimit: torrent.downloadLimit,
            dlLimited: torrent.downloadLimited,
            upLimit: torrent.uploadLimit,
            upLimited: torrent.uploadLimited
        )
    }

    /// Set per-torrent speed limits (KB/s). Pass 0 to disable the limit.
    func setTorrentSpeedLimits(hash: String, dlLimitKBps: Int, dlLimited: Bool, upLimitKBps: Int, upLimited: Bool) async throws {
        var setArgs: [String: Any] = [
            "ids": [hash],
            "downloadLimited": dlLimited,
            "uploadLimited": upLimited
        ]
        if dlLimited {
            setArgs["downloadLimit"] = dlLimitKBps
        }
        if upLimited {
            setArgs["uploadLimit"] = upLimitKBps
        }

        _ = try await performRequest("torrent-set", arguments: setArgs, responseType: EmptyArgs.self)
    }
}

extension TransmissionClient {
    func setTaskTags(hashes: [String], tags: [String]) async throws {
        let normalizedHashes = hashes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedHashes.isEmpty else { return }

        _ = try await performRequest(
            "torrent-set",
            arguments: [
                "ids": normalizedHashes,
                "labels": normalizeTags(tags)
            ],
            responseType: EmptyArgs.self
        )
    }

    func fetchServerTags() async throws -> [String] {
        var merged = Set<String>()
        merged.formUnion(loadFallbackTagCatalog())

        if let sessionLabels = try await fetchSessionLabels() {
            merged.formUnion(sessionLabels)
        }

        let torrentLabels = try await fetchTorrentLabels()
            .flatMap(\.labels)
        merged.formUnion(torrentLabels)

        return merged
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func createServerTags(_ tags: [String]) async throws {
        let normalized = normalizeTags(tags)
        guard !normalized.isEmpty else { return }

        let existingSessionLabels = try await fetchSessionLabels()
        let existingTorrentLabels = try await fetchTorrentLabels()
            .flatMap(\.labels)
        let fallbackLabels = loadFallbackTagCatalog()

        let merged = Set(existingSessionLabels ?? [])
            .union(existingTorrentLabels)
            .union(fallbackLabels)
            .union(normalized)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if existingSessionLabels == nil {
            saveFallbackTagCatalog(merged)
            return
        }

        try await setSessionLabels(merged)
        saveFallbackTagCatalog(merged)
    }

    func deleteServerTags(_ tags: [String]) async throws {
        let normalized = Set(normalizeTags(tags))
        guard !normalized.isEmpty else { return }

        if let existing = try await fetchSessionLabels() {
            let updated = existing.filter { !normalized.contains($0) }
            try await setSessionLabels(updated)
        }

        try await removeTagsFromTorrents(normalized)

        let fallback = Set(loadFallbackTagCatalog())
        let updatedFallback = fallback.subtracting(normalized)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        saveFallbackTagCatalog(updatedFallback)
    }

    func renameServerTag(oldName: String, newName: String) async throws {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }
        guard trimmedOld != trimmedNew else { return }

        if let existing = try await fetchSessionLabels() {
            var updated = existing.filter { $0 != trimmedOld }
            if !updated.contains(trimmedNew) {
                updated.append(trimmedNew)
            }
            updated.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            try await setSessionLabels(updated)
        }

        try await renameTagAcrossTorrents(oldName: trimmedOld, newName: trimmedNew)

        var fallback = loadFallbackTagCatalog()
        if let index = fallback.firstIndex(of: trimmedOld) {
            fallback[index] = trimmedNew
        } else if !fallback.contains(trimmedNew) {
            fallback.append(trimmedNew)
        }
        saveFallbackTagCatalog(normalizeTags(fallback))
    }

    private struct TransmissionLabelItem: Decodable {
        let id: Int
        let labels: [String]
    }

    private func fetchSessionLabels() async throws -> [String]? {
        struct SessionGetLabels: Decodable {
            let labels: [String]?
        }

        let args = try await performRequest("session-get", arguments: nil, responseType: SessionGetLabels.self)
        guard let labels = args.labels else { return nil }
        return normalizeTags(labels)
    }

    private func setSessionLabels(_ labels: [String]) async throws {
        _ = try await performRequest("session-set", arguments: ["labels": labels], responseType: EmptyArgs.self)
    }

    private func fetchTorrentLabels() async throws -> [TransmissionLabelItem] {
        struct TorrentGetLabels: Decodable {
            struct Item: Decodable {
                let id: Int
                let labels: [String]?
            }

            let torrents: [Item]
        }

        let args = try await performRequest(
            "torrent-get",
            arguments: ["fields": ["id", "labels"]],
            responseType: TorrentGetLabels.self
        )

        return args.torrents.map {
            TransmissionLabelItem(
                id: $0.id,
                labels: normalizeTags($0.labels ?? [])
            )
        }
    }

    private func removeTagsFromTorrents(_ tags: Set<String>) async throws {
        guard !tags.isEmpty else { return }
        let torrents = try await fetchTorrentLabels()

        for torrent in torrents {
            let nextLabels = torrent.labels.filter { !tags.contains($0) }
            if nextLabels != torrent.labels {
                _ = try await performRequest(
                    "torrent-set",
                    arguments: ["ids": [torrent.id], "labels": nextLabels],
                    responseType: EmptyArgs.self
                )
            }
        }
    }

    private func renameTagAcrossTorrents(oldName: String, newName: String) async throws {
        let torrents = try await fetchTorrentLabels()

        for torrent in torrents {
            guard torrent.labels.contains(oldName) else { continue }
            let replaced = torrent.labels.map { $0 == oldName ? newName : $0 }
            let deduplicated = normalizeTags(replaced)
            _ = try await performRequest(
                "torrent-set",
                arguments: ["ids": [torrent.id], "labels": deduplicated],
                responseType: EmptyArgs.self
            )
        }
    }

    private var fallbackTagCatalogKey: String {
        "transmission.tag.catalog.\(config.id.uuidString)"
    }

    private func loadFallbackTagCatalog() -> [String] {
        let raw = UserDefaults.standard.array(forKey: fallbackTagCatalogKey) as? [String] ?? []
        return normalizeTags(raw)
    }

    private func saveFallbackTagCatalog(_ tags: [String]) {
        UserDefaults.standard.set(normalizeTags(tags), forKey: fallbackTagCatalogKey)
    }

    fileprivate func normalizeTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Batch Operations

    /// Build ids argument. Pass `["all"]` to omit ids and operate on every torrent.
    private func batchArgs(_ hashes: [String], extra: [String: Any] = [:]) -> [String: Any] {
        var args = extra
        if !(hashes.count == 1 && hashes[0] == "all") {
            args["ids"] = hashes
        }
        return args
    }

    func pauseTasks(hashes: [String]) async throws {
        _ = try await performRequest("torrent-stop", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
    }

    func resumeTasks(hashes: [String]) async throws {
        _ = try await performRequest("torrent-start", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
    }

    func deleteTasks(hashes: [String], withData: Bool) async throws {
        _ = try await performRequest("torrent-remove", arguments: batchArgs(hashes, extra: ["delete-local-data": withData]), responseType: EmptyArgs.self)
    }

    func recheckTasks(hashes: [String]) async throws {
        _ = try await performRequest("torrent-verify", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
    }

    func reannounceTasks(hashes: [String]) async throws {
        _ = try await performRequest("torrent-reannounce", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
    }

    func forceStartTasks(hashes: [String]) async throws {
        do {
            _ = try await performRequest("torrent-start-now", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
        } catch {
            _ = try await performRequest("torrent-start", arguments: batchArgs(hashes), responseType: EmptyArgs.self)
        }
    }
}

// Helpers
struct TransmissionRPCResponse<T: Decodable>: Decodable {
    let result: String
    let arguments: T?
}

struct EmptyArgs: Decodable {}
