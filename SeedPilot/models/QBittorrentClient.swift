//
//  QBittorrentClient.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation

class QBittorrentClient: NSObject, TorrentClient {
    private let config: ServerConfig

    private lazy var session: URLSession = {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieStorage = HTTPCookieStorage.shared
        sessionConfig.httpCookieAcceptPolicy = .always
        // Use NetworkManager instance with specific SSL setting
        let delegate = NetworkManager(allowInsecureSSL: config.allowInsecureSSL)
        return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }()

    // Cookie 存储
    private var cookies: [HTTPCookie] = []

    init(config: ServerConfig) {
        self.config = config
        super.init()
    }

    private var apiPathPrefix: String {
        let trimmed = config.rpcPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/api/v2" }

        let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        // Backward compatibility: older qB servers may still persist the Transmission default.
        return normalized == "/transmission/rpc" ? "/api/v2" : normalized
    }

    private func apiURL(_ path: String) -> URL? {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "\(getBaseURL())\(apiPathPrefix)\(normalizedPath)")
    }

    private func formURLEncode(_ value: String) -> String {
        // application/x-www-form-urlencoded: reserved chars escaped, spaces encoded as "+"
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=%/?")
        return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
            .replacingOccurrences(of: "%20", with: "+")
    }

    // MARK: - Auth

    func login() async throws {
        let address = config.baseURL

        guard let url = apiURL("auth/login") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // qBittorrent 登录是 application/x-www-form-urlencoded
        let bodyString = "username=\(formURLEncode(config.username))&password=\(formURLEncode(config.resolvedPassword))"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // 设置 Referer 以防某些版本检查
        request.setValue(address, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0, userInfo: nil))
        }

        // qBittorrent 成功返回 "Ok."，失败一般是 "Fails."
        if let responseString = String(data: data, encoding: .utf8), responseString.trimmingCharacters(in: .whitespacesAndNewlines) == "Ok." {
            return
        } else {
             // Check if cookie was set anyway (sometimes 200 OK but content varies)
            if httpResponse.statusCode == 200 {
                 // Check if SID cookie is present in storage
                 if let cookies = session.configuration.httpCookieStorage?.cookies(for: url), cookies.contains(where: { $0.name == "SID" }) {
                     return
                 }
                 // If status 200 but no SID and not "Ok.", might be failure
            }
            throw TorrentClientError.authenticationFailed
        }
    }

    // MARK: - Fetch List

    func fetchTorrents() async throws -> [TorrentTask] {
        guard let url = apiURL("torrents/info") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                throw TorrentClientError.authenticationFailed
            }
            throw TorrentClientError.apiError("Fetch failed")
        }

        let serverID = config.id
        do {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let decoder = JSONDecoder()
                        let qbTasks = try decoder.decode([QBTask].self, from: data)

                        let mapped = qbTasks.map { task -> TorrentTask in
                            let progress = task.progress
                            let size = Int64(task.size)
                            let downloadSpeed = Int64(task.dlspeed)
                            let uploadSpeed = Int64(task.upspeed)
                            let seedingTime = TimeInterval(task.seeding_time ?? 0)
                            let numSeeds = task.num_seeds ?? 0
                            let totalSeeds = task.num_complete ?? 0
                            let numPeers = task.num_leechs ?? 0
                            let totalPeers = task.num_incomplete ?? 0
                            let ratio = task.ratio ?? 0.0

                            let displayText = TorrentTaskDisplayText.build(
                                title: task.name,
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

                            let completionTimestamp: Int? = {
                                if let completionOn = task.completion_on, completionOn > 0 {
                                    return completionOn
                                }
                                if let seenComplete = task.seen_complete, seenComplete > 0 {
                                    return seenComplete
                                }
                                return nil
                            }()

                            let normalizedState = task.state
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .lowercased()
                            let mappedStatus = Self.mapQBState(task.state)
                            let errorStateToken = mappedStatus == .error ? normalizedState : nil

                            return TorrentTask(
                                hash: task.hash,
                                name: task.name,
                                progress: progress,
                                size: size,
                                downloadSpeed: downloadSpeed,
                                uploadSpeed: uploadSpeed,
                                remainingTime: task.eta == 8640000 ? -1 : TimeInterval(task.eta),
                                status: mappedStatus,
                                errorCode: nil,
                                errorMessage: errorStateToken,
                                serverID: serverID,
                                tracker: task.tracker ?? "",
                                savePath: task.save_path ?? "",
                                category: task.category ?? "",
                                tags: task.tags ?? "",
                                downloaded: task.downloaded ?? 0,
                                uploaded: task.uploaded ?? 0,
                                isSequential: task.seq_dl,
                                isFirstLastPiecePriority: task.f_l_piece_prio,
                                completionDate: completionTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                seedingTime: seedingTime,
                                addedTime: Date(timeIntervalSince1970: TimeInterval(task.added_on ?? 0)),
                                resolutionBadge: ResolutionExtractor.extractBadge(from: task.name),
                                displayText: displayText,
                                numSeeds: numSeeds,
                                totalSeeds: totalSeeds,
                                numPeers: numPeers,
                                totalPeers: totalPeers,
                                ratio: ratio
                            )
                        }

                        continuation.resume(returning: mapped)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            print("Decoding error: \(error)")
            throw TorrentClientError.decodingError
        }
    }

    // MARK: - Actions

    // MARK: - Actions

    private func getBaseURL() -> String {
        config.baseURL
    }

    private func configureRequest(_ request: inout URLRequest) {
        let baseURL = getBaseURL()
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue(baseURL, forHTTPHeaderField: "Origin")
    }

    func addTorrents(_ urls: [String], options: AddTorrentOptions) async throws {
        guard let url = apiURL("torrents/add") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequest(&request)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Prepare parameters
        var params: [String: String] = [
            "urls": urls.joined(separator: "\n"),
            "paused": options.isPaused ? "true" : "false",
            "stopped": options.isPaused ? "true" : "false",
            "skip_checking": options.skipHashCheck ? "true" : "false",
            "sequentialDownload": options.isSequential ? "true" : "false",
            "firstLastPiecePrio": options.isFirstLastPiecePriority ? "true" : "false"
        ]
        
        if !options.savePath.isEmpty {
            params["savepath"] = options.savePath
        }
        if !options.category.isEmpty {
            params["category"] = options.category
        }
        if !options.tags.isEmpty {
            params["tags"] = options.tags.joined(separator: ",")
        }

        request.httpBody = createMultipartBody(boundary: boundary, data: nil, fileName: nil, params: params)

        print("[SeedPilot] addTorrents URL: \(urls)")

        let (data, response) = try await session.data(for: request)
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }
        
        print("[SeedPilot] addTorrents response: HTTP \(httpResponse.statusCode), body: \(responseBody)")
        
        if httpResponse.statusCode == 403 {
            throw TorrentClientError.authenticationFailed
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("Add Torrents failed: HTTP \(httpResponse.statusCode) \(responseBody)")
        }
        
        // qBittorrent returns "Fails." in body when add actually failed
        if responseBody.trimmingCharacters(in: .whitespacesAndNewlines) == "Fails." {
            throw TorrentClientError.apiError("qBittorrent rejected the torrent URL. Check that the URL is a valid torrent/magnet link.")
        }
    }

    func addTorrentFile(_ fileURL: URL, options: AddTorrentOptions) async throws {
        guard let url = apiURL("torrents/add") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        configureRequest(&request)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "savepath": options.savePath,
            "category": options.category,
            "tags": options.tags.joined(separator: ","),
            "paused": options.isPaused ? "true" : "false",
            "stopped": options.isPaused ? "true" : "false",
            "skip_checking": options.skipHashCheck ? "true" : "false",
            "sequentialDownload": options.isSequential ? "true" : "false",
             "firstLastPiecePrio": options.isFirstLastPiecePriority ? "true" : "false"
        ]

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw TorrentClientError.apiError("Cannot read file data")
        }

        request.httpBody = createMultipartBody(boundary: boundary, data: fileData, fileName: fileURL.lastPathComponent, params: params)

        let (data, response) = try await session.data(for: request)
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }
        
        if httpResponse.statusCode == 403 {
            throw TorrentClientError.authenticationFailed
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("Add Torrent File failed: HTTP \(httpResponse.statusCode) \(responseBody)")
        }
        
        if responseBody.trimmingCharacters(in: .whitespacesAndNewlines) == "Fails." {
            throw TorrentClientError.apiError("qBittorrent rejected the torrent file.")
        }
    }

    private func createMultipartBody(boundary: String, data: Data?, fileName: String?, params: [String: String]) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for (key, value) in params {
            body.append("--\(boundary + lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak + lineBreak)")
            body.append("\(value + lineBreak)")
        }

        if let data = data, let fileName = fileName {
            body.append("--\(boundary + lineBreak)")
            body.append("Content-Disposition: form-data; name=\"torrents\"; filename=\"\(fileName)\"\(lineBreak)")
            body.append("Content-Type: application/x-bittorrent\(lineBreak + lineBreak)")
            body.append(data)
            body.append(lineBreak)
        }

        body.append("--\(boundary)--\(lineBreak)")
        return body
    }

    func pauseTask(hash: String) async throws {
        do {
            try await performAction(endpoint: "pause", hashes: hash)
        } catch {
            // Compatibility fallback for some qB API variants/proxies.
            try await performAction(endpoint: "stop", hashes: hash)
        }
    }

    func resumeTask(hash: String) async throws {
        do {
            try await performAction(endpoint: "resume", hashes: hash)
        } catch {
            // Compatibility fallback for some qB API variants/proxies.
            try await performAction(endpoint: "start", hashes: hash)
        }
    }

    func deleteTask(hash: String, withData: Bool) async throws {
        try await performAction(endpoint: "delete", hashes: hash, extraParams: ["deleteFiles": withData ? "true" : "false"])
    }

    // MARK: - Advanced Management

    func recheckTask(hash: String) async throws {
        try await performAction(endpoint: "recheck", hashes: hash)
    }

    func reannounceTask(hash: String) async throws {
        try await performAction(endpoint: "reannounce", hashes: hash)
    }

    func toggleSequentialDownload(hash: String) async throws {
        try await performAction(endpoint: "toggleSequentialDownload", hashes: hash)
    }

    func toggleFirstLastPiecePriority(hash: String) async throws {
        try await performAction(endpoint: "toggleFirstLastPiecePrio", hashes: hash)
    }

    func renameTask(hash: String, newName: String) async throws {
        try await performAction(
            endpoint: "rename",
            hashes: hash,
            hashParameterKey: "hash",
            extraParams: ["name": newName]
        )
    }

    // MARK: - Core Control Logic

    func forceStartTask(hash: String) async throws {
        do {
            try await performAction(endpoint: "setForceStart", hashes: hash, extraParams: ["value": "true"])
        } catch {
            // Compatibility fallback for older qB variants/proxies.
            do {
                try await performAction(endpoint: "resume", hashes: hash)
            } catch {
                try await performAction(endpoint: "start", hashes: hash)
            }
        }
    }

    func setLocation(hash: String, newLocation: String) async throws {
        try await performAction(endpoint: "setLocation", hashes: hash, extraParams: ["location": newLocation])
    }

    func editTrackers(hash: String, newTrackers: String) async throws {
        let normalizedHash = normalizeHashes(hash)
        let targetTrackers = normalizedTrackerURLs(from: newTrackers)
        guard !targetTrackers.isEmpty else {
            throw TorrentClientError.apiError("No valid tracker URL provided")
        }

        let existingTrackers = (try? await fetchTrackerURLs(hash: normalizedHash)) ?? []
        if !existingTrackers.isEmpty {
            let urlsToRemove = existingTrackers.filter { !targetTrackers.contains($0) }
            if !urlsToRemove.isEmpty {
                try await performAction(
                    endpoint: "removeTrackers",
                    hashes: normalizedHash,
                    hashParameterKey: "hash",
                    extraParams: ["urls": urlsToRemove.joined(separator: "|")]
                )
            }
        }

        let urlsToAdd = existingTrackers.isEmpty
            ? targetTrackers
            : targetTrackers.filter { !existingTrackers.contains($0) }

        if !urlsToAdd.isEmpty {
            try await performAction(
                endpoint: "addTrackers",
                hashes: normalizedHash,
                extraParams: ["urls": urlsToAdd.joined(separator: "\n")]
            )
        }
    }

    func fetchTrackers(hash: String) async throws -> [TorrentTrackerInfo] {
        let normalizedHash = normalizeHashes(hash)
        let encodedHash = normalizedHash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalizedHash
        let data = try await performServerSettingsRequest(path: "trackers?hash=\(encodedHash)")
        let trackers = try JSONDecoder().decode([QBTrackerEntry].self, from: data)

        var output: [TorrentTrackerInfo] = []
        output.reserveCapacity(max(trackers.count, 1))

        for (index, tracker) in trackers.enumerated() {
            let rawURL = tracker.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayURL = rawURL.isEmpty ? "--" : rawURL
            let normalizedMessage = tracker.msg?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (normalizedMessage?.isEmpty == false) ? normalizedMessage : nil

            output.append(
                TorrentTrackerInfo(
                    id: "\(tracker.tier ?? -1)|\(displayURL)|\(index)",
                    tier: tracker.tier,
                    url: displayURL,
                    status: Self.mapQBTrackerStatus(tracker.status),
                    peers: tracker.num_peers,
                    seeds: tracker.num_seeds,
                    leeches: tracker.num_leeches,
                    downloaded: tracker.num_downloaded,
                    message: message
                )
            )
        }

        return output
    }

    private struct QBTrackerEntry: Decodable {
        let url: String?
        let status: Int?
        let tier: Int?
        let num_peers: Int?
        let num_seeds: Int?
        let num_leeches: Int?
        let num_downloaded: Int?
        let msg: String?
    }

    private func fetchTrackerURLs(hash: String) async throws -> [String] {
        let encodedHash = hash.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hash
        let data = try await performServerSettingsRequest(path: "trackers?hash=\(encodedHash)")
        let trackers = try JSONDecoder().decode([QBTrackerEntry].self, from: data)

        var seen = Set<String>()
        var result: [String] = []
        for tracker in trackers {
            guard let raw = tracker.url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            guard isLikelyTrackerURL(raw) else { continue }
            let key = raw.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(raw)
        }
        return result
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

    private func performAction(
        endpoint: String,
        hashes: String,
        hashParameterKey: String = "hashes",
        extraParams: [String: String] = [:]
    ) async throws {
        let normalizedHashes = normalizeHashes(hashes)

        func makeRequest() throws -> URLRequest {
            guard let url = apiURL("torrents/\(endpoint)") else {
                throw TorrentClientError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            configureRequest(&request)

            var params = [hashParameterKey: normalizedHashes]
            for (key, value) in extraParams {
                params[key] = value
            }

            let bodyString = params.map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-_.~")
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }.joined(separator: "&")

            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            return request
        }

        var request = try makeRequest()
        let (firstData, firstResponse) = try await session.data(for: request)

        guard let firstHTTP = firstResponse as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        if firstHTTP.statusCode == 403 {
            try await login()
            request = try makeRequest()
            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                let status = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: retryData, encoding: .utf8) ?? ""
                throw TorrentClientError.apiError("\(endpoint) failed: HTTP \(status) \(body)")
            }
            let retryBody = String(data: retryData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if retryBody == "Fails." {
                throw TorrentClientError.apiError("\(endpoint) failed: \(retryBody)")
            }
            return
        }

        guard firstHTTP.statusCode == 200 else {
            let body = String(data: firstData, encoding: .utf8) ?? ""
            throw TorrentClientError.apiError("\(endpoint) failed: HTTP \(firstHTTP.statusCode) \(body)")
        }

        let firstBody = String(data: firstData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstBody == "Fails." {
            throw TorrentClientError.apiError("\(endpoint) failed: \(firstBody)")
        }
    }

    private func normalizeHashes(_ hashes: String) -> String {
        if hashes == "all" {
            return hashes
        }
        return hashes
            .split(separator: "|")
            .map { String($0).lowercased() }
            .joined(separator: "|")
    }

    // MARK: - Heartbeat

    func checkConnection() async throws -> String {
        guard let url = apiURL("app/version") else {
            throw TorrentClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5 // Short timeout for heartbeat

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Need to login?
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                throw TorrentClientError.authenticationFailed
            }
            throw TorrentClientError.apiError("Heartbeat failed")
        }

        if let version = String(data: data, encoding: .utf8) {
            return version
        }
        return "Unknown"
    }

    // MARK: - File Management

    func getFiles(hash: String) async throws -> [TorrentFile] {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let data = try await performServerSettingsRequest(path: "files?hash=\(normalizedHash)")

        struct QBFile: Decodable {
            let name: String
            let size: Int64
            let progress: Double
            let priority: Int
        }

        let qbFiles = try JSONDecoder().decode([QBFile].self, from: data)
        return qbFiles.enumerated().map { index, file in
            let downloaded = Int64(Double(file.size) * file.progress)
            let priority: FilePriority
            switch file.priority {
            case 0:  priority = .doNotDownload
            case 6:  priority = .high
            case 7:  priority = .maximum
            default: priority = .normal
            }
            return TorrentFile(
                index: index,
                name: file.name,
                size: file.size,
                downloaded: downloaded,
                progress: file.progress,
                priority: priority
            )
        }
    }

    func setFilePriority(hash: String, fileIndices: [Int], priority: FilePriority) async throws {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let qbPriority: Int
        switch priority {
        case .doNotDownload: qbPriority = 0
        case .normal:        qbPriority = 1
        case .high:          qbPriority = 6
        case .maximum:       qbPriority = 7
        }

        try await performAction(
            endpoint: "filePrio",
            hashes: normalizedHash,
            hashParameterKey: "hash",
            extraParams: [
                "id": fileIndices.map(String.init).joined(separator: "|"),
                "priority": "\(qbPriority)"
            ]
        )
    }

    // MARK: - Helpers

    private func mapStatus(state: String) -> TorrentStatus {
        Self.mapQBState(state)
    }

    private static func mapQBState(_ state: String) -> TorrentStatus {
        let normalizedState = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedState {
        case "metadl", "allocating", "downloading", "dl", "stalleddl", "forceddl", "forcedmetadl":
            return .downloading
        case "queueddl", "queuedup":
            return .queued
        case "uploading", "stalledup", "forcedup", "up":
            return .seeding
        case "pauseddl", "pausedup", "paused":
            return .paused
        case "checkingdl", "checkingup", "checkingresumedata", "moving":
            return .checking
        case "error", "missingfiles", "unregistered", "unregisteredtorrent", "unknown":
            return .error
        case "completed":
            return .completed
        default:
            return .paused
        }
    }

    private static func mapQBTrackerStatus(_ status: Int?) -> TorrentTrackerStatus {
        switch status {
        case 0:
            return .disabled
        case 1:
            return .notContacted
        case 2:
            return .working
        case 3:
            return .updating
        case 4:
            return .failed
        default:
            return .unknown
        }
    }
}

extension QBittorrentClient {
    func setTaskCategory(hashes: [String], category: String) async throws {
        let normalizedHashes = hashes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalizedHashes.isEmpty else { return }

        try await performAction(
            endpoint: "setCategory",
            hashes: normalizedHashes.joined(separator: "|"),
            extraParams: ["category": category.trimmingCharacters(in: .whitespacesAndNewlines)]
        )
    }

    func addTaskTags(hashes: [String], tags: [String]) async throws {
        let normalizedHashes = hashes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let normalizedTags = normalizedServerTags(tags)
        guard !normalizedHashes.isEmpty, !normalizedTags.isEmpty else { return }

        try await performAction(
            endpoint: "addTags",
            hashes: normalizedHashes.joined(separator: "|"),
            extraParams: ["tags": normalizedTags.joined(separator: ",")]
        )
    }

    func removeTaskTags(hashes: [String], tags: [String]) async throws {
        let normalizedHashes = hashes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let normalizedTags = normalizedServerTags(tags)
        guard !normalizedHashes.isEmpty, !normalizedTags.isEmpty else { return }

        try await performAction(
            endpoint: "removeTags",
            hashes: normalizedHashes.joined(separator: "|"),
            extraParams: ["tags": normalizedTags.joined(separator: ",")]
        )
    }

    struct ServerCategoryEntry: Identifiable, Hashable {
        let name: String
        let savePath: String

        var id: String { name }
    }

    func fetchServerCategories() async throws -> [ServerCategoryEntry] {
        let data = try await performServerSettingsRequest(path: "categories")

        struct CategoryInfo: Decodable {
            let name: String?
            let savePath: String?
        }

        let decoded = try JSONDecoder().decode([String: CategoryInfo].self, from: data)
        return decoded.map { key, value in
            ServerCategoryEntry(
                name: value.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (value.name ?? key) : key,
                savePath: value.savePath ?? ""
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createServerCategory(name: String, savePath: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        _ = try await performServerSettingsRequest(
            path: "createCategory",
            method: "POST",
            formParams: [
                "category": trimmed,
                "savePath": savePath
            ]
        )
    }

    func updateServerCategory(name: String, savePath: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        _ = try await performServerSettingsRequest(
            path: "editCategory",
            method: "POST",
            formParams: [
                "category": trimmed,
                "savePath": savePath
            ]
        )
    }

    func renameServerCategory(oldName: String, newName: String, savePath: String) async throws {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }

        if trimmedOld == trimmedNew {
            try await updateServerCategory(name: trimmedNew, savePath: savePath)
            return
        }

        try await createServerCategory(name: trimmedNew, savePath: savePath)
        try await deleteServerCategories([trimmedOld])
    }

    func deleteServerCategories(_ names: [String]) async throws {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        _ = try await performServerSettingsRequest(
            path: "removeCategories",
            method: "POST",
            formParams: ["categories": normalized.joined(separator: "\n")]
        )
    }

    func fetchServerTags() async throws -> [String] {
        let data = try await performServerSettingsRequest(path: "tags")

        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return normalizedServerTags(array)
        }

        if let plain = String(data: data, encoding: .utf8) {
            let fallback = plain
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { String($0) }
            return normalizedServerTags(fallback)
        }

        return []
    }

    func createServerTags(_ tags: [String]) async throws {
        let normalized = normalizedServerTags(tags)
        guard !normalized.isEmpty else { return }

        _ = try await performServerSettingsRequest(
            path: "createTags",
            method: "POST",
            formParams: ["tags": normalized.joined(separator: ",")]
        )
    }

    func deleteServerTags(_ tags: [String]) async throws {
        let normalized = normalizedServerTags(tags)
        guard !normalized.isEmpty else { return }

        _ = try await performServerSettingsRequest(
            path: "deleteTags",
            method: "POST",
            formParams: ["tags": normalized.joined(separator: ",")]
        )
    }

    func renameServerTag(oldName: String, newName: String) async throws {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }
        guard trimmedOld != trimmedNew else { return }

        _ = try await performServerSettingsRequest(
            path: "renameTag",
            method: "POST",
            formParams: [
                "oldTag": trimmedOld,
                "newTag": trimmedNew
            ]
        )
    }

    // MARK: - Connection Settings

    func getConnectionSettings() async throws -> ConnectionSettings {
        let data = try await performAppSettingsRequest(path: "app/preferences")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TorrentClientError.decodingError
        }

        return ConnectionSettings(
            listenPort: intValue(json["listen_port"]) ?? 0,
            useUPnP: boolValue(json["upnp"]) ?? false,
            maxConnections: intValue(json["max_connec"]) ?? 0,
            maxConnectionsPerTorrent: intValue(json["max_connec_per_torrent"]) ?? 0,
            maxUploads: intValue(json["max_uploads"]),
            maxUploadsPerTorrent: intValue(json["max_uploads_per_torrent"]),
            bittorrentProtocol: intValue(json["bittorrent_protocol"]) ?? 0,
            torrentQueueEnabled: boolValue(json["queueing_enabled"]),
            maxActiveDownloads: intValue(json["max_active_downloads"]),
            maxActiveUploads: intValue(json["max_active_uploads"]),
            maxActiveTorrents: intValue(json["max_active_torrents"])
        )
    }

    func setConnectionSettings(_ settings: ConnectionSettings) async throws {
        let normalizedPort = min(max(settings.listenPort, 1), 65535)
        let normalizedProtocol = min(max(settings.bittorrentProtocol, 0), 2)

        let payload: [String: Any] = [
            "listen_port": normalizedPort,
            "upnp": settings.useUPnP,
            "max_connec": settings.maxConnections,
            "max_connec_per_torrent": settings.maxConnectionsPerTorrent,
            "max_uploads": settings.maxUploads ?? 0,
            "max_uploads_per_torrent": settings.maxUploadsPerTorrent ?? 0,
            "bittorrent_protocol": normalizedProtocol,
            "queueing_enabled": settings.torrentQueueEnabled ?? false,
            "max_active_downloads": settings.maxActiveDownloads ?? 0,
            "max_active_uploads": settings.maxActiveUploads ?? 0,
            "max_active_torrents": settings.maxActiveTorrents ?? 0
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TorrentClientError.apiError("setPreferences payload encoding failed")
        }

        _ = try await performAppSettingsRequest(
            path: "app/setPreferences",
            method: "POST",
            formParams: ["json": jsonString]
        )
    }

    func getDownloadSettings() async throws -> DownloadSettings {
        let data = try await performAppSettingsRequest(path: "app/preferences")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TorrentClientError.decodingError
        }

        return DownloadSettings(
            savePath: stringValue(json["save_path"]) ?? "",
            appendExtension: boolValue(json["append_extension"]) ?? false,
            useTempPath: boolValue(json["temp_path_enabled"]) ?? false,
            tempPath: stringValue(json["temp_path"]) ?? "",
            preallocateAll: boolValue(json["preallocate_all"]),
            cacheSizeMB: nil
        )
    }

    func setDownloadSettings(_ settings: DownloadSettings) async throws {
        var payload: [String: Any] = [
            "save_path": settings.savePath,
            "append_extension": settings.appendExtension,
            "temp_path_enabled": settings.useTempPath,
            "temp_path": settings.tempPath
        ]
        if let preallocateAll = settings.preallocateAll {
            payload["preallocate_all"] = preallocateAll
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TorrentClientError.apiError("setPreferences payload encoding failed")
        }

        _ = try await performAppSettingsRequest(
            path: "app/setPreferences",
            method: "POST",
            formParams: ["json": jsonString]
        )
    }

    // MARK: - Per-Torrent Speed Limits

    /// Fetch current per-torrent speed limits (Bytes/s). Returns (dlLimit, upLimit).
    /// A value of 0 means unlimited.
    func fetchTorrentSpeedLimits(hash: String) async throws -> (dlLimit: Int, upLimit: Int) {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let data = try await performServerSettingsRequest(
            path: "properties?hash=\(normalizedHash)"
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TorrentClientError.decodingError
        }

        let dlLimit = (json["dl_limit"] as? Int) ?? 0
        let upLimit = (json["up_limit"] as? Int) ?? 0
        return (dlLimit: max(0, dlLimit), upLimit: max(0, upLimit))
    }

    /// Set per-torrent speed limits (Bytes/s). Pass 0 to remove the limit.
    func setTorrentSpeedLimits(hash: String, dlLimitBytesPerSec: Int, upLimitBytesPerSec: Int) async throws {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        try await performAction(
            endpoint: "setDownloadLimit",
            hashes: normalizedHash,
            extraParams: ["limit": "\(dlLimitBytesPerSec)"]
        )
        try await performAction(
            endpoint: "setUploadLimit",
            hashes: normalizedHash,
            extraParams: ["limit": "\(upLimitBytesPerSec)"]
        )
    }

    private func performAppSettingsRequest(
        path: String,
        method: String = "GET",
        formParams: [String: String] = [:]
    ) async throws -> Data {
        func makeRequest() throws -> URLRequest {
            guard let url = apiURL(path) else {
                throw TorrentClientError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            configureRequest(&request)

            if method == "POST" {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = formEncodedBody(formParams)
            }

            return request
        }

        var request = try makeRequest()
        let (firstData, firstResponse) = try await session.data(for: request)

        guard let firstHTTP = firstResponse as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        if firstHTTP.statusCode == 403 {
            try await login()
            request = try makeRequest()
            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                let status = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: retryData, encoding: .utf8) ?? ""
                throw TorrentClientError.apiError("\(path) failed: HTTP \(status) \(body)")
            }
            return retryData
        }

        guard firstHTTP.statusCode == 200 else {
            let body = String(data: firstData, encoding: .utf8) ?? ""
            throw TorrentClientError.apiError("\(path) failed: HTTP \(firstHTTP.statusCode) \(body)")
        }

        return firstData
    }

    private func performServerSettingsRequest(
        path: String,
        method: String = "GET",
        formParams: [String: String] = [:]
    ) async throws -> Data {
        func makeRequest() throws -> URLRequest {
            guard let url = apiURL("torrents/\(path)") else {
                throw TorrentClientError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            configureRequest(&request)

            if method == "POST" {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = formEncodedBody(formParams)
            }

            return request
        }

        var request = try makeRequest()
        let (firstData, firstResponse) = try await session.data(for: request)

        guard let firstHTTP = firstResponse as? HTTPURLResponse else {
            throw TorrentClientError.networkError(NSError(domain: "Invalid Response", code: 0))
        }

        if firstHTTP.statusCode == 403 {
            try await login()
            request = try makeRequest()
            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                let status = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: retryData, encoding: .utf8) ?? ""
                throw TorrentClientError.apiError("\(path) failed: HTTP \(status) \(body)")
            }
            return retryData
        }

        guard firstHTTP.statusCode == 200 else {
            let body = String(data: firstData, encoding: .utf8) ?? ""
            throw TorrentClientError.apiError("\(path) failed: HTTP \(firstHTTP.statusCode) \(body)")
        }

        return firstData
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            let lower = value.lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func normalizedServerTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func formEncodedBody(_ params: [String: String]) -> Data {
        let encoded = params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-_.~")
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")

        return Data(encoded.utf8)
    }
}

// MARK: - Decodable Model

struct QBTask: Decodable {
    let hash: String
    let name: String
    let size: Int64
    let progress: Double
    let dlspeed: Int
    let upspeed: Int
    let state: String
    let eta: Int
    let tracker: String?
    let save_path: String?
    let category: String?
    let tags: String?
    let downloaded: Int64?
    let uploaded: Int64?
    let seq_dl: Bool?
    let f_l_piece_prio: Bool?
    let completion_on: Int? // Timestamp
    let seen_complete: Int? // Timestamp
    let added_on: Int?
    let num_seeds: Int?
    let num_complete: Int?
    let num_leechs: Int?
    let num_incomplete: Int?
    let ratio: Double?
    let seeding_time: Int?
}

enum TorrentClientError: Error {
    case invalidURL
    case networkError(Error)
    case authenticationFailed
    case apiError(String)
    case decodingError
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
