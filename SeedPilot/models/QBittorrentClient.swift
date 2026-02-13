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
        // Use NetworkManager.shared for SSL bypass
        return URLSession(configuration: sessionConfig, delegate: NetworkManager.shared, delegateQueue: nil)
    }()
    
    // Cookie 存储
    private var cookies: [HTTPCookie] = []
    
    init(config: ServerConfig) {
        self.config = config
        super.init()
    }
    
    // MARK: - Auth
    
    func login() async throws {
        // Ensure address has protocol
        var address = config.address
        if !address.hasPrefix("http") {
             address = "http://" + address
        }
        
        // Remove trailing slash if present
        if address.hasSuffix("/") {
            address = String(address.dropLast())
        }

        guard let url = URL(string: "\(address):\(config.port)/api/v2/auth/login") else {
            throw TorrentClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // qBittorrent 登录是 application/x-www-form-urlencoded
        let bodyString = "username=\(config.username)&password=\(config.password)"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // 设置 Referer 以防某些版本检查
        request.setValue(address, forHTTPHeaderField: "Referer")
        
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
        var address = config.address
        if !address.hasPrefix("http") { address = "http://" + address }
        if address.hasSuffix("/") { address = String(address.dropLast()) }
        
        guard let url = URL(string: "\(address):\(config.port)/api/v2/torrents/info") else {
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
        
        let decoder = JSONDecoder()
        do {
            let qbTasks = try decoder.decode([QBTask].self, from: data)
            
            return qbTasks.map { task -> TorrentTask in
                return TorrentTask(
                    id: task.hash,
                    name: task.name,
                    progress: task.progress,
                    size: Int64(task.size),
                    downloadSpeed: Int64(task.dlspeed),
                    uploadSpeed: Int64(task.upspeed),
                    remainingTime: task.eta == 8640000 ? -1 : TimeInterval(task.eta),
                    status: mapStatus(state: task.state),
                    serverID: config.id
                )
            }
        } catch {
            print("Decoding error: \(error)")
            throw TorrentClientError.decodingError
        }
    }
    
    // MARK: - Actions
    
    private func getBaseURL() -> String {
        var address = config.address
        if !address.hasPrefix("http") { address = "http://" + address }
        if address.hasSuffix("/") { address = String(address.dropLast()) }
        return "\(address):\(config.port)"
    }
    
    func addMagnetLink(_ link: String) async throws {
        guard let url = URL(string: "\(getBaseURL())/api/v2/torrents/add") else {
            throw TorrentClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // URL encode the magnet link properly
        let bodyString = "urls=\(link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? link)"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("Add failed")
        }
    }
    
    func pauseTask(hash: String) async throws {
        try await performAction(endpoint: "pause", hashes: hash)
    }
    
    func resumeTask(hash: String) async throws {
        try await performAction(endpoint: "resume", hashes: hash)
    }
    
    func deleteTask(hash: String, withData: Bool) async throws {
        try await performAction(endpoint: "delete", hashes: hash, extraParams: ["deleteFiles": withData ? "true" : "false"])
    }
    
    private func performAction(endpoint: String, hashes: String, extraParams: [String: String] = [:]) async throws {
        guard let url = URL(string: "\(getBaseURL())/api/v2/torrents/\(endpoint)") else {
            throw TorrentClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        var params = ["hashes": hashes]
        // Manual merge since Dictionary.merge implies mutating current dict
        for (key, value) in extraParams {
            params[key] = value
        }
        
        let bodyString = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TorrentClientError.apiError("\(endpoint) failed")
        }
    }
    
    // MARK: - Heartbeat
    
    func checkConnection() async throws -> String {
        guard let url = URL(string: "\(getBaseURL())/api/v2/app/version") else {
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
    
    // MARK: - Helpers
    
    private func mapStatus(state: String) -> TorrentStatus {
        switch state {
        case "metaDL", "allocating", "downloading", "dl", "stalledDL":
            return .downloading
        case "uploading", "stalledUP", "forcedUP", "up":
            return .seeding
        case "pausedDL", "pausedUP", "paused":
            return .paused
        case "checkingDL", "checkingUP", "checkingResumeData", "moving":
            return .checking
        case "error", "missingFiles":
            return .error
        case "completed":
            return .completed
        case "queuedDL", "queuedUP":
            return .downloading // View as downloading/active
        default:
            return .paused
        }
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
}

enum TorrentClientError: Error {
    case invalidURL
    case networkError(Error)
    case authenticationFailed
    case apiError(String)
    case decodingError
}
