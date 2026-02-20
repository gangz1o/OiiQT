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
        sessionConfig.waitsForConnectivity = true
        sessionConfig.timeoutIntervalForRequest = 20
        sessionConfig.timeoutIntervalForResource = 40
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
        let authString = "\(config.username):\(config.password)"
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

    private func performRequest<T: Decodable>(_ method: String, arguments: [String: Any]?, responseType: T.Type) async throws -> T {
        guard let url = getRPCURL() else { throw TorrentClientError.invalidURL }

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

                let decoder = JSONDecoder()
                let rpcResponse = try decoder.decode(TransmissionRPCResponse<T>.self, from: data)

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
                let downloadDir: String
                let percentDone: Double
                let eta: Int
                let downloadedEver: Int64
                let uploadedEver: Int64
                let uploadRatio: Double
                let peersConnected: Int
                let secondsSeeding: Int? // Optional
                let tracker: String?
                let trackers: [Tracker]?
            }
            let torrents: [Item]
        }

        let fields = [
            "id", "hashString", "name", "totalSize", "rateDownload", "rateUpload",
            "status", "downloadDir", "percentDone", "eta", "downloadedEver",
            "uploadedEver", "uploadRatio", "peersConnected", "secondsSeeding",
            "tracker", "trackers"
        ]

        let args = try await performRequest("torrent-get", arguments: ["fields": fields], responseType: TorrentGet.self)

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

        return args.torrents.map { item in
            let trackerURL = pickTrackerURL(primary: item.tracker, trackers: item.trackers)

            return TorrentTask(
                id: item.hashString,
                name: item.name,
                progress: item.percentDone,
                size: item.totalSize,
                downloadSpeed: item.rateDownload,
                uploadSpeed: item.rateUpload,
                remainingTime: TimeInterval(item.eta),
                status: mapStatus(item.status),
                serverID: config.id,
                tracker: trackerURL,
                savePath: item.downloadDir,
                tags: "", // Transmission doesn't handle tags same way as qB, uses labels in newer versions. Skipping.
                downloaded: item.downloadedEver,
                uploaded: item.uploadedEver,
                isSequential: nil,
                isFirstLastPiecePriority: nil,
                completionDate: nil,
                seedingTime: TimeInterval(item.secondsSeeding ?? 0),
                addedTime: Date(), // Not returned by default fields, can add 'addedDate'
                numSeeds: 0, // Need to parse 'peers' detailed or 'trackerStats' for seeds.
                totalSeeds: 0,
                numPeers: item.peersConnected,
                totalPeers: 0,
                ratio: item.uploadRatio
            )
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
         _ = try await performRequest("torrent-start-now", arguments: ["ids": [hash]], responseType: EmptyArgs.self)
    }

    func setLocation(hash: String, newLocation: String) async throws {
         _ = try await performRequest("torrent-set-location", arguments: ["ids": [hash], "location": newLocation, "move": true], responseType: EmptyArgs.self)
    }

    func editTrackers(hash: String, newTrackers: String) async throws {
         // Complex: 'torrent-set' with 'trackerAdd', 'trackerRemove', or 'trackerReplace'
    }

    // MARK: - Helpers

    private func mapStatus(_ status: Int) -> TorrentStatus {
        // Transmission Status:
        // 0: Stopped, 1: Check Wait, 2: Check, 3: Download Wait, 4: Download, 5: Seed Wait, 6: Seed
        switch status {
        case 0: return .paused
        case 1, 2: return .checking
        case 3, 4: return .downloading
        case 5, 6: return .seeding
        default: return .error
        }
    }
}

// Helpers
struct TransmissionRPCResponse<T: Decodable>: Decodable {
    let result: String
    let arguments: T?
}

struct EmptyArgs: Decodable {}
