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

enum SettingsRoute: Hashable {
    case dashboardCustomization
    case proFeatures
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
    var tasksRevision: Int = 0
    var isRefreshingTasks: Bool = false
    var hasInitialDataLoaded: Bool = false
    var downloadingTaskBadgeCount: Int = 0

    var activeServerId: UUID?

    // Navigation
    var selectedTab: AppTab = .dashboard
    var settingsRoute: SettingsRoute?

    // Analytics
    var speedHistory: [SpeedPoint] = []

    // Client Cache
    private var clients: [UUID: TorrentClient] = [:]
    private var lastKnownServerStatus: [UUID: Bool] = [:]
    private var serverStatusFailureStreak: [UUID: Int] = [:]
    private var autoRefreshTask: Task<Void, Never>?
    private var refreshDataInFlightCount: Int = 0

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
            hasInitialDataLoaded = servers.isEmpty
            // Start auto-refresh
            startAutoRefresh()
        } catch {
            print("Failed to load servers: \(error)")
            hasInitialDataLoaded = true
        }
    }

    /// Sync servers from UI Query (to ensure we have latest list including new additions)
    @MainActor
    func updateServers(_ newServers: [ServerConfig]) {
        self.servers = newServers
        let validServerIDs = Set(newServers.map(\.id))
        lastKnownServerStatus = lastKnownServerStatus.filter { validServerIDs.contains($0.key) }
        serverStatusFailureStreak = serverStatusFailureStreak.filter { validServerIDs.contains($0.key) }
    }

    /// 启动自动刷新 (每 2 秒)
    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            // Initial fetch
            await self.refreshData()

            // Periodic fetch
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                guard !Task.isCancelled else { break }
                await self.refreshData()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// 刷新所有服务器的任务 (对应 User Request: refreshData)
    func refreshData() async {
        await MainActor.run {
            refreshDataInFlightCount += 1
            isRefreshingTasks = true
        }
        defer {
            Task { @MainActor in
                self.refreshDataInFlightCount = max(0, self.refreshDataInFlightCount - 1)
                self.isRefreshingTasks = self.refreshDataInFlightCount > 0
            }
        }

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
                    markServerOnline(server)

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
                            markServerOnline(server)

                            server.totalSeedingCount = tasks.filter { $0.status == .seeding }.count
                            server.totalDownloadingCount = tasks.filter { $0.status == .downloading }.count
                            server.totalSeedingSize = tasks.filter { $0.status == .seeding }.reduce(0) { $0 + $1.size }

                            let totalUploaded = tasks.reduce(0) { $0 + $1.uploaded }
                            let totalDownloaded = tasks.reduce(0) { $0 + $1.downloaded }
                            server.totalRatio = totalDownloaded > 0
                                ? Double(totalUploaded) / Double(totalDownloaded)
                                : 0.0
                        }
                    } catch {
                        print("Auth retry failed for \(server.name): \(error)")
                        await MainActor.run {
                            markServerFailure(server)
                        }
                    }
                } else {
                    print("Fetch failed for \(server.name): \(error)")
                    await MainActor.run {
                        markServerFailure(server)
                    }
                }
            } catch {
                print("Unknown error for \(server.name): \(error)")
                await MainActor.run {
                    markServerFailure(server)
                }
            }
        }

        let finalTasks = gatheredTasks
        // Defer heavy list data update to RunLoop.default — auto-pauses during scroll
        RunLoop.main.perform(inModes: [.default]) { [self] in
            if self.allTasks != finalTasks {
                self.allTasks = finalTasks
                self.tasksRevision &+= 1
            }
        }
        // Essential state flags must update immediately (not deferred)
        await MainActor.run {
            let newDownloadingCount = finalTasks.filter { $0.status == .downloading }.count
            if self.downloadingTaskBadgeCount != newDownloadingCount {
                self.downloadingTaskBadgeCount = newDownloadingCount
            }
            self.hasInitialDataLoaded = true

            // Record History
            let now = Date()
            let down = finalTasks.reduce(0) { $0 + $1.downloadSpeed }
            let up = finalTasks.reduce(0) { $0 + $1.uploadSpeed }

            if self.speedHistory.count > 60 {
                self.speedHistory.removeFirst()
            }
            self.speedHistory.append(SpeedPoint(date: now, download: down, upload: up))
        }
    }

    func checkServerStatus() {
        for server in servers {
            let client = getClient(for: server)

            Task {
                var success = false

                for attempt in 0...2 {
                    do {
                        _ = try await client.checkConnection()
                        success = true
                        break
                    } catch {
                        if attempt < 2 {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                }

                await MainActor.run {
                    if success {
                        markServerOnline(server)
                    } else {
                        markServerFailure(server)
                    }
                }
            }
        }
    }

    @MainActor
    private func markServerOnline(_ server: ServerConfig) {
        server.isOnline = true
        lastKnownServerStatus[server.id] = true
        serverStatusFailureStreak[server.id] = 0
    }

    @MainActor
    private func markServerFailure(_ server: ServerConfig) {
        let streak = (serverStatusFailureStreak[server.id] ?? 0) + 1
        serverStatusFailureStreak[server.id] = streak

        let previousOnline = lastKnownServerStatus[server.id] ?? (server.isOnline == true)
        let keepOnline = previousOnline && streak <= 1
        server.isOnline = keepOnline
        lastKnownServerStatus[server.id] = keepOnline
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

    // MARK: - Server Category / Tag Settings

    func fetchServerCategories(for server: ServerConfig) async throws -> [QBittorrentClient.ServerCategoryEntry] {
        guard server.type == .qBittorrent else { return [] }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        return try await client.fetchServerCategories()
    }

    func createServerCategory(for server: ServerConfig, name: String, savePath: String) async throws {
        guard server.type == .qBittorrent else {
            throw TorrentClientError.apiError("Current server does not support categories.")
        }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        try await client.createServerCategory(name: name, savePath: savePath)
        await refreshData()
    }

    func updateServerCategory(for server: ServerConfig, oldName: String, newName: String, savePath: String) async throws {
        guard server.type == .qBittorrent else {
            throw TorrentClientError.apiError("Current server does not support categories.")
        }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        try await client.renameServerCategory(oldName: oldName, newName: newName, savePath: savePath)
        await refreshData()
    }

    func deleteServerCategory(for server: ServerConfig, name: String) async throws {
        guard server.type == .qBittorrent else {
            throw TorrentClientError.apiError("Current server does not support categories.")
        }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        try await client.deleteServerCategories([name])
        await refreshData()
    }

    func fetchServerTags(for server: ServerConfig) async throws -> [String] {
        switch server.type {
        case .qBittorrent:
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }
            return try await client.fetchServerTags()
        case .transmission:
            guard let client = getClient(for: server) as? TransmissionClient else {
                throw TorrentClientError.apiError("Failed to initialize Transmission client.")
            }
            return try await client.fetchServerTags()
        }
    }

    func createServerTag(for server: ServerConfig, name: String) async throws {
        switch server.type {
        case .qBittorrent:
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }
            try await client.createServerTags([name])
        case .transmission:
            guard let client = getClient(for: server) as? TransmissionClient else {
                throw TorrentClientError.apiError("Failed to initialize Transmission client.")
            }
            try await client.createServerTags([name])
        }
        await refreshData()
    }

    func updateServerTag(for server: ServerConfig, oldName: String, newName: String) async throws {
        switch server.type {
        case .qBittorrent:
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }
            try await client.renameServerTag(oldName: oldName, newName: newName)
        case .transmission:
            guard let client = getClient(for: server) as? TransmissionClient else {
                throw TorrentClientError.apiError("Failed to initialize Transmission client.")
            }
            try await client.renameServerTag(oldName: oldName, newName: newName)
        }
        await refreshData()
    }

    func deleteServerTag(for server: ServerConfig, name: String) async throws {
        switch server.type {
        case .qBittorrent:
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }
            try await client.deleteServerTags([name])
        case .transmission:
            guard let client = getClient(for: server) as? TransmissionClient else {
                throw TorrentClientError.apiError("Failed to initialize Transmission client.")
            }
            try await client.deleteServerTags([name])
        }
        await refreshData()
    }

    // MARK: - Task Category / Tag Actions

    func fetchTaskCategoryOptions(for task: TorrentTask) async throws -> [String] {
        try await fetchTaskCategoryOptions(for: Set([task]))
    }

    func fetchTaskCategoryOptions(for tasks: Set<TorrentTask>) async throws -> [String] {
        var merged = Set<String>()
        let grouped = Dictionary(grouping: tasks, by: \.serverID)

        for (serverID, _) in grouped {
            guard let server = servers.first(where: { $0.id == serverID }) else {
                throw TorrentClientError.apiError("Server not found.")
            }
            guard server.type == .qBittorrent else {
                throw TorrentClientError.apiError("Current server does not support categories.")
            }
            let categories = try await fetchServerCategories(for: server).map(\.name)
            merged.formUnion(categories)
        }

        return merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func fetchTaskTagOptions(for task: TorrentTask) async throws -> [String] {
        try await fetchTaskTagOptions(for: Set([task]))
    }

    func fetchTaskTagOptions(for tasks: Set<TorrentTask>) async throws -> [String] {
        var merged = Set<String>()
        let grouped = Dictionary(grouping: tasks, by: \.serverID)

        for (serverID, groupTasks) in grouped {
            guard let server = servers.first(where: { $0.id == serverID }) else { continue }
            let serverTags = try await fetchServerTags(for: server)
            merged.formUnion(serverTags)
            for task in groupTasks {
                merged.formUnion(normalizedTagSet(from: task.tags))
            }
        }

        return merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func applyCategory(_ category: String, to task: TorrentTask) async throws {
        try await applyCategory(category, to: Set([task]))
    }

    func applyCategory(_ category: String, to tasks: Set<TorrentTask>) async throws {
        let grouped = Dictionary(grouping: tasks, by: \.serverID)
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

        for (serverID, groupTasks) in grouped {
            guard let server = servers.first(where: { $0.id == serverID }) else { continue }
            guard server.type == .qBittorrent else {
                throw TorrentClientError.apiError("Current server does not support categories.")
            }
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }

            try await client.setTaskCategory(
                hashes: groupTasks.map(\.hash),
                category: normalizedCategory
            )
        }

        await refreshData()
    }

    func applyTags(_ tags: [String], to task: TorrentTask) async throws {
        try await applyTags(tags, to: Set([task]))
    }

    func applyTags(_ tags: [String], to tasks: Set<TorrentTask>) async throws {
        let targetTags = normalizeTags(tags)
        let targetTagSet = Set(targetTags)
        let grouped = Dictionary(grouping: tasks, by: \.serverID)

        for (serverID, groupTasks) in grouped {
            guard let server = servers.first(where: { $0.id == serverID }) else { continue }

            switch server.type {
            case .qBittorrent:
                guard let client = getClient(for: server) as? QBittorrentClient else {
                    throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
                }
                for task in groupTasks {
                    let currentTagSet = normalizedTagSet(from: task.tags)
                    let toAdd = Array(targetTagSet.subtracting(currentTagSet))
                    let toRemove = Array(currentTagSet.subtracting(targetTagSet))
                    if !toAdd.isEmpty {
                        try await client.addTaskTags(hashes: [task.hash], tags: toAdd)
                    }
                    if !toRemove.isEmpty {
                        try await client.removeTaskTags(hashes: [task.hash], tags: toRemove)
                    }
                }

            case .transmission:
                guard let client = getClient(for: server) as? TransmissionClient else {
                    throw TorrentClientError.apiError("Failed to initialize Transmission client.")
                }
                try await client.setTaskTags(hashes: groupTasks.map(\.hash), tags: targetTags)
            }
        }

        await refreshData()
    }

    // MARK: - Task Actions


    // MARK: - Actions

    func addTorrents(
        _ urls: [String],
        options: AddTorrentOptions,
        to targetServerID: UUID? = nil,
        enforcePausedFallback: Bool = false
    ) async throws {
        // Determine target server
        let finalServerID = targetServerID ?? activeServerId

        guard let serverID = finalServerID, let server = servers.first(where: { $0.id == serverID }) else {
            // Default to first server if none selected and no active
             if let first = servers.first {
                 let client = getClient(for: first)
                 let beforeHashes = await captureTaskHashesIfNeeded(
                    client: client,
                    options: options,
                    enforcePausedFallback: enforcePausedFallback
                 )
                 try await addTorrentsWithRetry(client: client, urls: urls, options: options)
                 await pauseNewlyAddedTorrentsIfNeeded(
                    client: client,
                    beforeHashes: beforeHashes,
                    options: options,
                    enforcePausedFallback: enforcePausedFallback
                 )
                 try await Task.sleep(nanoseconds: 500_000_000)
                 await refreshData()
                 return
             }
            return
        }

        let client = getClient(for: server)
        let beforeHashes = await captureTaskHashesIfNeeded(
            client: client,
            options: options,
            enforcePausedFallback: enforcePausedFallback
        )
        try await addTorrentsWithRetry(client: client, urls: urls, options: options)
        await pauseNewlyAddedTorrentsIfNeeded(
            client: client,
            beforeHashes: beforeHashes,
            options: options,
            enforcePausedFallback: enforcePausedFallback
        )

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

    private func captureTaskHashesIfNeeded(
        client: TorrentClient,
        options: AddTorrentOptions,
        enforcePausedFallback: Bool
    ) async -> Set<String>? {
        guard enforcePausedFallback, options.isPaused else { return nil }
        guard let tasks = try? await client.fetchTorrents() else { return nil }
        return Set(tasks.map(\.hash))
    }

    private func pauseNewlyAddedTorrentsIfNeeded(
        client: TorrentClient,
        beforeHashes: Set<String>?,
        options: AddTorrentOptions,
        enforcePausedFallback: Bool
    ) async {
        guard enforcePausedFallback, options.isPaused, let beforeHashes else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)

        guard let tasks = try? await client.fetchTorrents() else { return }
        let newlyAddedHashes = tasks
            .map(\.hash)
            .filter { !beforeHashes.contains($0) }

        for hash in newlyAddedHashes {
            try? await client.pauseTask(hash: hash)
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
                try await client.pauseTask(hash: task.hash)
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
                try await client.resumeTask(hash: task.hash)
                await refreshData()
            } catch {
                print("Failed to resume: \(error)")
            }
        }
    }

    func deleteTasks(_ tasks: Set<TorrentTask>) {
        deleteTasks(tasks, withData: true)
    }

    func deleteTasks(_ tasks: Set<TorrentTask>, withData: Bool) {
        performBatchAction(tasks) { client, hash in
            try await client.deleteTask(hash: hash, withData: withData)
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
        performTaskAction(task) { client, id in
            try await client.renameTask(hash: id, newName: newName)
            await self.refreshData()
        }
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
        guard canPerformServerScopedBatchMutation(tasks) else {
            print("Batch set location blocked: mixed server selection.")
            return
        }
        performBatchAction(tasks) { client, hash in
            try await client.setLocation(hash: hash, newLocation: newLocation)
        }
    }

    func editTrackersBatch(_ tasks: Set<TorrentTask>, newTrackers: String) {
        guard canPerformServerScopedBatchMutation(tasks) else {
            print("Batch edit trackers blocked: mixed server selection.")
            return
        }
        performBatchAction(tasks) { client, hash in
            try await client.editTrackers(hash: hash, newTrackers: newTrackers)
        }
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
                try await action(client, task.hash)
                // Optional: await refreshData() or let auto-refresh handle it
            } catch {
                print("Task action failed: \(error)")
            }
        }
    }

    func canPerformServerScopedBatchMutation(_ tasks: Set<TorrentTask>) -> Bool {
        !hasMultipleServers(in: tasks)
    }

    private func hasMultipleServers(in tasks: Set<TorrentTask>) -> Bool {
        Set(tasks.map(\.serverID)).count > 1
    }

    private func performBatchAction(_ tasks: Set<TorrentTask>, action: @escaping (TorrentClient, String) async throws -> Void) {
        // Group by server and dispatch against the matching client.
        let grouped = Dictionary(grouping: tasks, by: { $0.serverID })
        guard !grouped.isEmpty else { return }

        Task {
            for (serverID, serverTasks) in grouped {
                guard let server = servers.first(where: { $0.id == serverID }) else { continue }
                let client = getClient(for: server)

                for task in serverTasks {
                    do {
                        try await action(client, task.hash)
                    } catch {
                        print("Batch action failed for server \(server.name), task \(task.hash): \(error)")
                    }
                }
            }
            await self.refreshData()
        }
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func normalizedTagSet(from raw: String) -> Set<String> {
        Set(
            raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}
