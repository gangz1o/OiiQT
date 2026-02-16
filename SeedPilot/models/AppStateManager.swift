//
//  AppStateManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation
import SwiftData
import Observation
import SwiftUI

enum AppTab: Int {
    case dashboard, transfers, rss, settings
}

struct SpeedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let download: Int64
    let upload: Int64
}

@Observable
class AppStateManager {
    var servers: [ServerConfig] = []
    var allTasks: [TorrentTask] = []

    var activeServerId: UUID?

    // Navigation
    var selectedTab: AppTab = .dashboard

    // Analytics
    var speedHistory: [SpeedPoint] = []

    // Client Cache
    private var clients: [UUID: TorrentClient] = [:]

    // MARK: - Computed Properties

    var displayedTasks: [TorrentTask] {
        if let id = activeServerId {
            return allTasks.filter { $0.serverID == id }
        }
        return allTasks
    }

    var activeServerName: String? {
        guard let id = activeServerId else { return nil }
        return servers.first(where: { $0.id == id })?.name
    }

    var activeServerType: ServerType? {
        guard let id = activeServerId else { return nil }
        return servers.first(where: { $0.id == id })?.type
    }

    /// 显示的任务总下载速度 (Bytes/s)
    var displayedDownloadSpeed: Int64 {
        displayedTasks.reduce(0) { $0 + $1.downloadSpeed }
    }

    /// 显示的任务总上传速度 (Bytes/s)
    var displayedUploadSpeed: Int64 {
        displayedTasks.reduce(0) { $0 + $1.uploadSpeed }
    }

    // Deprecated exact totals if we only use displayed
    var totalDownloadSpeed: Int64 { displayedDownloadSpeed }
    var totalUploadSpeed: Int64 { displayedUploadSpeed }

    // MARK: - Asset Stats
    var displayedSeedingCount: Int {
        displayedTasks.filter { $0.status == .seeding }.count
    }

    var displayedSeedingSize: Int64 {
        displayedTasks.filter { $0.status == .seeding }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Data Management

    /// 从 SwiftData 加载服务器列表 (App launch)
    @MainActor
    func loadServers(context: ModelContext) {
        let descriptor = FetchDescriptor<ServerConfig>(sortBy: [SortDescriptor(\.name)])
        do {
            servers = try context.fetch(descriptor)
            // Start auto-refresh
            startAutoRefresh()
        } catch {
            print("Failed to load servers: \(error)")
        }
    }

    /// Sync servers from UI Query (to ensure we have latest list including new additions)
    @MainActor
    func updateServers(_ newServers: [ServerConfig]) {
        self.servers = newServers
    }

    /// 启动自动刷新 (每 2 秒)
    func startAutoRefresh() {
        Task {
            // Initial fetch
            await refreshData()

            // Periodic fetch
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await refreshData()
            }
        }
    }

    /// 刷新所有服务器的任务 (对应 User Request: refreshData)
    func refreshData() async {
        var gatheredTasks: [TorrentTask] = []

        // Parallel fetching could be done with TaskGroup, but for now serial is safer for debug
        for server in servers {
            let client = getClient(for: server)
            do {
                // Try fetch
                let tasks = try await client.fetchTorrents()
                gatheredTasks.append(contentsOf: tasks)

                // Mark online
                await MainActor.run {
                    server.isOnline = true

                    // Update stats
                    server.totalSeedingCount = tasks.filter { $0.status == .seeding }.count
                    server.totalDownloadingCount = tasks.filter { $0.status == .downloading }.count
                    server.totalSeedingSize = tasks.filter { $0.status == .seeding }.reduce(0) { $0 + $1.size }

                    let totalUploaded = tasks.reduce(0) { $0 + $1.uploaded }
                    let totalDownloaded = tasks.reduce(0) { $0 + $1.downloaded }

                    if totalDownloaded > 0 {
                        server.totalRatio = Double(totalUploaded) / Double(totalDownloaded)
                    } else {
                        server.totalRatio = 0.0
                    }
                }
            } catch let error as TorrentClientError {
                // If auth failed, try login and retry
                if case .authenticationFailed = error {
                    do {
                        try await client.login()
                        let tasks = try await client.fetchTorrents()
                        gatheredTasks.append(contentsOf: tasks)

                        // Mark online after retry success
                        await MainActor.run {
                            server.isOnline = true
                        }
                    } catch {
                        print("Auth retry failed for \(server.name): \(error)")
                        await MainActor.run { server.isOnline = false }
                    }
                } else {
                    print("Fetch failed for \(server.name): \(error)")
                    await MainActor.run { server.isOnline = false }
                }
            } catch {
                print("Unknown error for \(server.name): \(error)")
                await MainActor.run { server.isOnline = false }
            }
        }

        let finalTasks = gatheredTasks
        await MainActor.run {
            self.allTasks = finalTasks

            // Record History
            let now = Date()
            let down = finalTasks.reduce(0) { $0 + $1.downloadSpeed }
            let up = finalTasks.reduce(0) { $0 + $1.uploadSpeed }

            // Limit history to last 60 points (2 minutes if 2s interval)
            // Or more? Area chart looks better with more data.
            // 300 points = 10 minutes.
            if self.speedHistory.count > 60 {
                self.speedHistory.removeFirst()
            }
            self.speedHistory.append(SpeedPoint(date: now, download: down, upload: up))
        }
    }

    func checkServerStatus() {
        for server in servers {
            let client = getClient(for: server)
            // Set to nil to show breathing animation
            server.isOnline = nil

            Task {
                do {
                    _ = try await client.checkConnection()
                    await MainActor.run { server.isOnline = true }
                } catch {
                    // Auth retry? checkConnection handles 403 by throwing auth failed,
                    // but we might want to try auto-login here too?
                    // For lightweight heartbeat, maybe just separate "Auth Failed" vs "Timeout"?
                    // User said "Timeout, check network".
                    // I'll stick to simple true/false for now as requested.
                    await MainActor.run { server.isOnline = false }
                }
            }
        }
    }

    private func getClient(for server: ServerConfig) -> TorrentClient {
        if let existing = clients[server.id] {
            return existing
        }

        let client: TorrentClient
        switch server.type {
        case .qBittorrent:
            client = QBittorrentClient(config: server)
        case .transmission:
            client = TransmissionClient(config: server)
        }
        clients[server.id] = client
        return client
    }

    // MARK: - Task Actions


    // MARK: - Actions

    func addTorrents(_ urls: [String], options: AddTorrentOptions, to targetServerID: UUID? = nil) async throws {
        // Determine target server
        let finalServerID = targetServerID ?? activeServerId

        guard let serverID = finalServerID, let server = servers.first(where: { $0.id == serverID }) else {
            // Default to first server if none selected and no active
             if let first = servers.first {
                 let client = getClient(for: first)
                 try await addTorrentsWithRetry(client: client, urls: urls, options: options)
                 try await Task.sleep(nanoseconds: 500_000_000)
                 await refreshData()
                 return
             }
            return
        }

        let client = getClient(for: server)
        try await addTorrentsWithRetry(client: client, urls: urls, options: options)

        // Refresh after short delay to let qBittorrent process the add
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await refreshData()
        print("[SeedPilot] Added torrents to \(server.name), triggered refresh.")
    }

    /// Add torrents with automatic re-login on auth failure
    private func addTorrentsWithRetry(client: TorrentClient, urls: [String], options: AddTorrentOptions) async throws {
        do {
            try await client.addTorrents(urls, options: options)
        } catch let error as TorrentClientError {
            if case .authenticationFailed = error {
                // Session expired, try login and retry
                print("[SeedPilot] Auth failed on addTorrents, re-logging in...")
                try await client.login()
                try await client.addTorrents(urls, options: options)
            } else {
                throw error
            }
        }
    }

    func addTorrentFile(_ fileURL: URL, options: AddTorrentOptions) async throws {
        guard let serverID = activeServerId, let server = servers.first(where: { $0.id == serverID }) else {
             if let first = servers.first {
                 let client = getClient(for: first)
                 try await client.addTorrentFile(fileURL, options: options)
                 try await Task.sleep(nanoseconds: 500_000_000)
                 await refreshData()
                 return
             }
            return
        }
        let client = getClient(for: server)
        try await client.addTorrentFile(fileURL, options: options)

        try await Task.sleep(nanoseconds: 1_000_000_000)
        await refreshData()
    }

    func pauseTask(_ task: TorrentTask) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)

        Task {
            do {
                try await client.pauseTask(hash: task.id)
                // Optionally optimistic update
                await refreshData()
            } catch {
                print("Failed to pause: \(error)")
            }
        }
    }

    func resumeTask(_ task: TorrentTask) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)

        Task {
            do {
                try await client.resumeTask(hash: task.id)
                await refreshData()
            } catch {
                print("Failed to resume: \(error)")
            }
        }
    }

    func deleteTasks(_ tasks: Set<TorrentTask>) {
        for task in tasks {
            guard let server = servers.first(where: { $0.id == task.serverID }) else { continue }
            let client = getClient(for: server)
            Task {
                do {
                    try await client.deleteTask(hash: task.id, withData: true)
                 } catch {
                    print("Failed to delete: \(error)")
                }
            }
        }
        // Refresh after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshData()
        }
    }

    // MARK: - Advanced Actions

    func deleteTask(_ task: TorrentTask, withData: Bool) {
        performTaskAction(task) { client, id in
            try await client.deleteTask(hash: id, withData: withData)
            // Refresh handled by performTaskAction or generic refresh
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.refreshData()
            }
        }
    }

    func recheckTask(_ task: TorrentTask) {
        performTaskAction(task) { client, id in try await client.recheckTask(hash: id) }
    }

    func reannounceTask(_ task: TorrentTask) {
        performTaskAction(task) { client, id in try await client.reannounceTask(hash: id) }
    }

    func toggleSequentialDownload(_ task: TorrentTask) {
         performTaskAction(task) { client, id in try await client.toggleSequentialDownload(hash: id) }
    }

    func toggleFirstLastPiecePriority(_ task: TorrentTask) {
         performTaskAction(task) { client, id in try await client.toggleFirstLastPiecePriority(hash: id) }
    }

    func renameTask(_ task: TorrentTask, newName: String) {
        performTaskAction(task) { client, id in try await client.renameTask(hash: id, newName: newName) }
    }

    func forceStartTask(_ task: TorrentTask) {
        performTaskAction(task) { client, id in try await client.forceStartTask(hash: id) }
    }

    func setLocation(_ task: TorrentTask, newLocation: String) {
        performTaskAction(task) { client, id in try await client.setLocation(hash: id, newLocation: newLocation) }
    }

    func editTrackers(_ task: TorrentTask, newTrackers: String) {
        performTaskAction(task) { client, id in try await client.editTrackers(hash: id, newTrackers: newTrackers) }
    }

    // MARK: - Batch Actions

    func pauseTasks(_ tasks: Set<TorrentTask>) {
        performBatchAction(tasks) { client, hashes in try await client.pauseTask(hash: hashes) }
    }

    func resumeTasks(_ tasks: Set<TorrentTask>) {
        performBatchAction(tasks) { client, hashes in try await client.resumeTask(hash: hashes) }
    }

    func setTransferLocationBatch(_ tasks: Set<TorrentTask>, newLocation: String) {
         performBatchAction(tasks) { client, hashes in try await client.setLocation(hash: hashes, newLocation: newLocation) }
    }

    func editTrackersBatch(_ tasks: Set<TorrentTask>, newTrackers: String) {
         performBatchAction(tasks) { client, hashes in try await client.editTrackers(hash: hashes, newTrackers: newTrackers) }
    }

    func forceStartTasks(_ tasks: Set<TorrentTask>) {
        performBatchAction(tasks) { client, hashes in try await client.forceStartTask(hash: hashes) }
    }

    func recheckTasks(_ tasks: Set<TorrentTask>) {
        performBatchAction(tasks) { client, hashes in try await client.recheckTask(hash: hashes) }
    }

    func reannounceTasks(_ tasks: Set<TorrentTask>) {
        performBatchAction(tasks) { client, hashes in try await client.reannounceTask(hash: hashes) }
    }

    private func performTaskAction(_ task: TorrentTask, action: @escaping (TorrentClient, String) async throws -> Void) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)
        Task {
            do {
                try await action(client, task.id)
                // Optional: await refreshData() or let auto-refresh handle it
            } catch {
                print("Task action failed: \(error)")
            }
        }
    }

    private func performBatchAction(_ tasks: Set<TorrentTask>, action: @escaping (TorrentClient, String) async throws -> Void) {
        // Group by server to optimize calls and handle multi-server selection
        let grouped = Dictionary(grouping: tasks, by: { $0.serverID })

        for (serverID, serverTasks) in grouped {
            guard let server = servers.first(where: { $0.id == serverID }) else { continue }
            let client = getClient(for: server)
            let hashes = serverTasks.map { $0.id }.joined(separator: "|")

            Task {
                do {
                    try await action(client, hashes)
                    await self.refreshData()
                } catch {
                    print("Batch action failed for server \(server.name): \(error)")
                }
            }
        }
    }
}
