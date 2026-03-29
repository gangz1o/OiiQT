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
import Combine

enum AppTab: Int {
    case dashboard, transfers, rss, moviePilot, settings
}

enum SettingsRoute: Hashable {
    case serverSettings
    case dashboardCustomization
    case proFeatures
    case tmdbAPIKey
    case moviePilotSettings
    case trackerAliases
}

struct SpeedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let download: Int64
    let upload: Int64
}

private struct ServerSpeedTotals: Sendable {
    let download: Int64
    let upload: Int64
}

private struct ServerTaskStats: Sendable {
    let seedingCount: Int
    let downloadingCount: Int
    let seedingSize: Int64
    let totalUploaded: Int64
    let totalDownloaded: Int64
    let totalDownloadSpeed: Int64
    let totalUploadSpeed: Int64
    let hasRecentFinishedTask: Bool
    let derivedCategories: [String]
    let derivedTags: [String]
}

private struct ServerSeedingTotals: Sendable {
    let count: Int
    let size: Int64
}

private struct ServerRefreshMutation: Sendable {
    enum Connectivity: Sendable {
        case success
        case failure
    }

    let serverID: UUID
    let connectivity: Connectivity
    let stats: ServerTaskStats?
}

private struct ProcessedServerTasks: Sendable {
    let tasks: [TorrentTask]
    let stats: ServerTaskStats
}

private struct MoviePilotRouteSnapshot: Equatable {
    let isProUser: Bool
    let isMoviePilotConfigured: Bool
    let isDebugTabOverrideEnabled: Bool

    var shouldMountTab: Bool {
        (isProUser && isMoviePilotConfigured) || isDebugTabOverrideEnabled
    }
}

private struct TaskRefreshSnapshot: Sendable {
    let allTasks: [TorrentTask]
    let displayedTasks: [TorrentTask]
    let activeServerID: UUID?
    let hasRecentFinishedAll: Bool
    let hasRecentFinishedByServerID: [UUID: Bool]
    let serverRefreshMutations: [ServerRefreshMutation]
    let aggregatedDownloadingCount: Int
    let aggregatedDownloadSpeed: Int64
    let aggregatedUploadSpeed: Int64
    let aggregatedSeedingCount: Int
    let aggregatedSeedingSize: Int64
    let aggregatedSpeedByServerID: [UUID: ServerSpeedTotals]
    let aggregatedSeedingByServerID: [UUID: ServerSeedingTotals]
    let publicationDate: Date
    /// O(1) fingerprint computed on background thread — avoids O(n) equality check on main thread.
    let allTasksHash: Int
}

@Observable
class AppStateManager {
    @ObservationIgnored
    private let moviePilotRouteQueue = DispatchQueue(label: "com.gangz1o.seedpilot.moviepilot-route", qos: .utility)

    @ObservationIgnored
    private var routeEngineCancellables: Set<AnyCancellable> = []

    @ObservationIgnored
    private var pendingTaskRefreshSnapshot: TaskRefreshSnapshot?

    @ObservationIgnored
    private var lastPublishedTasksHash: Int = 0

    @ObservationIgnored
    private var taskRefreshPublicationTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeRefreshSuspensionSources: Set<String> = []

    @ObservationIgnored
    private var refreshSuspensionCooldownDeadline: UInt64 = 0

    var servers: [ServerConfig] = []
    var allTasks: [TorrentTask] = []
    var tasksRevision: Int = 0
    var isRefreshingTasks: Bool = false
    var hasInitialDataLoaded: Bool = false
    var downloadingTaskBadgeCount: Int = 0
    var availableCategories: [String] = []
    var availableTags: [String] = []

    var activeServerId: UUID? {
        didSet { rebuildDisplayedTasks() }
    }

    // Navigation
    var selectedTab: AppTab = .dashboard
    var settingsRoute: SettingsRoute?
    private(set) var shouldMountMoviePilotTab = false
    private(set) var isMoviePilotFeatureUnlocked = false
    private(set) var isMoviePilotConfigured = false
    var shouldPresentMoviePilotUpgradeSheet = false

    // Analytics
    var speedHistory: [SpeedPoint] = []
    var hasRecentFinishedTasks: Bool {
        if let activeServerId {
            return hasRecentFinishedByServerID[activeServerId] ?? false
        }
        return hasRecentFinishedTasksAll
    }

    // Client Cache
    private var clients: [UUID: TorrentClient] = [:]
    private var autoRefreshTask: Task<Void, Never>?
    private var refreshDataInFlightCount: Int = 0
    private var totalDownloadSpeedCache: Int64 = 0
    private var totalUploadSpeedCache: Int64 = 0
    private var speedTotalsByServerID: [UUID: ServerSpeedTotals] = [:]
    private var totalSeedingCountCache: Int = 0
    private var totalSeedingSizeCache: Int64 = 0
    private var seedingTotalsByServerID: [UUID: ServerSeedingTotals] = [:]
    private var hasRecentFinishedTasksAll: Bool = false
    private var hasRecentFinishedByServerID: [UUID: Bool] = [:]
    private var taskDerivedCategoriesByServerID: [UUID: [String]] = [:]
    private var taskDerivedTagsByServerID: [UUID: [String]] = [:]
    private var serverCategoriesByServerID: [UUID: [String]] = [:]
    private var serverTagsByServerID: [UUID: [String]] = [:]
    private var taxonomyWarmupTasksByServerID: [UUID: Task<Void, Never>] = [:]
    private var taxonomyWarmupDatesByServerID: [UUID: Date] = [:]
    private let taxonomyWarmupTTL: TimeInterval = 300

    init() {
        configureRouteStateEngine()
    }

    private static var debugForceMoviePilotTab: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SeedPilotForceMoviePilotTab")
            || UserDefaults.standard.bool(forKey: "debug.moviepilot.forceTab")
#else
        false
#endif
    }

    // MARK: - Computed Properties

    /// Cached slice of allTasks for the active server.
    /// Updated only when allTasks or activeServerId changes — never computed inline.
    private(set) var displayedTasks: [TorrentTask] = []

    private func rebuildDisplayedTasks() {
        let rebuiltTasks = Self.makeDisplayedTasks(from: allTasks, activeServerID: activeServerId)
        if displayedTasks != rebuiltTasks {
            displayedTasks = rebuiltTasks
        }
    }

    nonisolated private static func makeDisplayedTasks(
        from tasks: [TorrentTask],
        activeServerID: UUID?
    ) -> [TorrentTask] {
        guard let activeServerID else { return tasks }
        return tasks.filter { $0.serverID == activeServerID }
    }

    /// Used by scrollable surfaces to temporarily suspend refresh-driven UI churn.
    @MainActor
    func setRefreshSuspension(_ isSuspended: Bool, source: String) {
        taskRefreshPublicationTask?.cancel()

        let didChange: Bool
        if isSuspended {
            didChange = activeRefreshSuspensionSources.insert(source).inserted
        } else {
            didChange = activeRefreshSuspensionSources.remove(source) != nil
        }

        guard didChange else { return }

        if isSuspended {
            refreshSuspensionCooldownDeadline = 0
            return
        }

        guard activeRefreshSuspensionSources.isEmpty else { return }

        refreshSuspensionCooldownDeadline = DispatchTime.now().uptimeNanoseconds + Self.refreshSuspensionCooldownNanos
        guard pendingTaskRefreshSnapshot != nil else { return }
        schedulePendingTaskRefreshPublication(minimumDelay: Self.refreshSuspensionCooldownNanos)
    }

    @MainActor
    var isRefreshSuspendedForScrolling: Bool {
        !activeRefreshSuspensionSources.isEmpty
    }

    @MainActor
    private func enqueueTaskRefreshSnapshot(_ snapshot: TaskRefreshSnapshot) {
        pendingTaskRefreshSnapshot = snapshot
        taskRefreshPublicationTask?.cancel()

        // Skip publication while a visible scrollable surface is moving.
        guard !isRefreshSuspendedForScrolling else { return }

        schedulePendingTaskRefreshPublication(minimumDelay: 120_000_000)
    }

    @MainActor
    private func publishPendingTaskRefreshSnapshot() {
        taskRefreshPublicationTask = nil

        guard let snapshot = pendingTaskRefreshSnapshot else { return }
        pendingTaskRefreshSnapshot = nil

        for mutation in snapshot.serverRefreshMutations {
            guard let server = servers.first(where: { $0.id == mutation.serverID }) else { continue }

            switch mutation.connectivity {
            case .success:
                markServerOnline(server)
                if let stats = mutation.stats {
                    applyServerTaskStats(stats, to: server)
                    ingestTaskDerivedTaxonomy(
                        categories: stats.derivedCategories,
                        tags: stats.derivedTags,
                        for: server
                    )
                    prewarmTaxonomyIfNeeded(for: server.id)
                }
            case .failure:
                markServerFailure(server)
            }
        }

        // Use O(1) hash comparison instead of O(n) deep equality on 100k TorrentTask structs.
        if snapshot.allTasksHash != lastPublishedTasksHash {
            lastPublishedTasksHash = snapshot.allTasksHash
            allTasks = snapshot.allTasks
            displayedTasks = activeServerId == snapshot.activeServerID
                ? snapshot.displayedTasks
                : Self.makeDisplayedTasks(from: snapshot.allTasks, activeServerID: activeServerId)
            tasksRevision &+= 1
        }

        if hasRecentFinishedTasksAll != snapshot.hasRecentFinishedAll {
            hasRecentFinishedTasksAll = snapshot.hasRecentFinishedAll
        }
        if hasRecentFinishedByServerID != snapshot.hasRecentFinishedByServerID {
            hasRecentFinishedByServerID = snapshot.hasRecentFinishedByServerID
        }

        if downloadingTaskBadgeCount != snapshot.aggregatedDownloadingCount {
            downloadingTaskBadgeCount = snapshot.aggregatedDownloadingCount
        }
        totalDownloadSpeedCache = snapshot.aggregatedDownloadSpeed
        totalUploadSpeedCache = snapshot.aggregatedUploadSpeed
        speedTotalsByServerID = snapshot.aggregatedSpeedByServerID
        totalSeedingCountCache = snapshot.aggregatedSeedingCount
        totalSeedingSizeCache = snapshot.aggregatedSeedingSize
        seedingTotalsByServerID = snapshot.aggregatedSeedingByServerID
        hasInitialDataLoaded = true

        if speedHistory.count > 60 {
            speedHistory.removeFirst()
        }
        speedHistory.append(
            SpeedPoint(
                date: snapshot.publicationDate,
                download: snapshot.aggregatedDownloadSpeed,
                upload: snapshot.aggregatedUploadSpeed
            )
        )
    }

    var activeServerName: String? {
        guard let id = activeServerId else { return nil }
        return servers.first(where: { $0.id == id })?.name
    }

    var activeServerType: ServerType? {
        guard let id = activeServerId else { return nil }
        return servers.first(where: { $0.id == id })?.type
    }

    var moviePilotSettingsEntryTrailingSymbolName: String {
        isMoviePilotFeatureUnlocked ? "chevron.right" : "lock.fill"
    }

    private func configureRouteStateEngine() {
        StoreManager.shared.$isProUser
            .prepend(StoreManager.shared.isProUser)
            .removeDuplicates()
            .combineLatest(
                MoviePilotServerStore.shared.configuredStatePublisher
                    .prepend(MoviePilotServerStore.shared.isMoviePilotConfigured)
                    .removeDuplicates()
            )
            .receive(on: moviePilotRouteQueue)
            .map { isProUser, isMoviePilotConfigured in
                MoviePilotRouteSnapshot(
                    isProUser: isProUser,
                    isMoviePilotConfigured: isMoviePilotConfigured,
                    isDebugTabOverrideEnabled: Self.debugForceMoviePilotTab
                )
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.isMoviePilotFeatureUnlocked = snapshot.isProUser
                self.isMoviePilotConfigured = snapshot.isMoviePilotConfigured
                self.shouldMountMoviePilotTab = snapshot.shouldMountTab

                if !snapshot.shouldMountTab, self.selectedTab == .moviePilot {
                    self.selectedTab = .dashboard
                }

#if DEBUG
                if snapshot.isDebugTabOverrideEnabled, self.selectedTab == .dashboard {
                    self.selectedTab = .moviePilot
                }
#endif
            }
            .store(in: &routeEngineCancellables)
    }

    nonisolated private static func configuredTaskRefreshInterval() -> TimeInterval? {
        let refreshRateDefaultsKey = "refreshRate"
        let defaultRefreshRateSeconds = 5
        let defaults = UserDefaults.standard
        let storedInterval = defaults.object(forKey: refreshRateDefaultsKey) as? Int
        let intervalSeconds = storedInterval ?? defaultRefreshRateSeconds
        guard intervalSeconds > 0 else { return nil }
        return TimeInterval(intervalSeconds)
    }

    @MainActor
    func handleMoviePilotSettingsEntryTap() {
        if !isMoviePilotFeatureUnlocked {
            shouldPresentMoviePilotUpgradeSheet = true
            return
        }

        selectedTab = .settings
        settingsRoute = .moviePilotSettings
    }

    @MainActor
    func consumeMoviePilotUpgradeSheetIntent() {
        shouldPresentMoviePilotUpgradeSheet = false
    }

    /// 显示的任务总下载速度 (Bytes/s)
    var displayedDownloadSpeed: Int64 {
        if let id = activeServerId {
            return speedTotalsByServerID[id]?.download ?? 0
        }
        return totalDownloadSpeedCache
    }

    /// 显示的任务总上传速度 (Bytes/s)
    var displayedUploadSpeed: Int64 {
        if let id = activeServerId {
            return speedTotalsByServerID[id]?.upload ?? 0
        }
        return totalUploadSpeedCache
    }

    // Deprecated exact totals if we only use displayed
    var totalDownloadSpeed: Int64 { displayedDownloadSpeed }
    var totalUploadSpeed: Int64 { displayedUploadSpeed }

    // MARK: - Asset Stats
    var displayedSeedingCount: Int {
        if let activeServerId {
            return seedingTotalsByServerID[activeServerId]?.count ?? 0
        }
        return totalSeedingCountCache
    }

    var displayedSeedingSize: Int64 {
        if let activeServerId {
            return seedingTotalsByServerID[activeServerId]?.size ?? 0
        }
        return totalSeedingSizeCache
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
        let removedServerIDs = Set(taxonomyWarmupTasksByServerID.keys).subtracting(validServerIDs)
        for serverID in removedServerIDs {
            taxonomyWarmupTasksByServerID[serverID]?.cancel()
        }
        speedTotalsByServerID = speedTotalsByServerID.filter { validServerIDs.contains($0.key) }
        seedingTotalsByServerID = seedingTotalsByServerID.filter { validServerIDs.contains($0.key) }
        hasRecentFinishedByServerID = hasRecentFinishedByServerID.filter { validServerIDs.contains($0.key) }
        taskDerivedCategoriesByServerID = taskDerivedCategoriesByServerID.filter { validServerIDs.contains($0.key) }
        taskDerivedTagsByServerID = taskDerivedTagsByServerID.filter { validServerIDs.contains($0.key) }
        serverCategoriesByServerID = serverCategoriesByServerID.filter { validServerIDs.contains($0.key) }
        serverTagsByServerID = serverTagsByServerID.filter { validServerIDs.contains($0.key) }
        taxonomyWarmupDatesByServerID = taxonomyWarmupDatesByServerID.filter { validServerIDs.contains($0.key) }
        taxonomyWarmupTasksByServerID = taxonomyWarmupTasksByServerID.filter { validServerIDs.contains($0.key) }
        refreshAvailableTaxonomySnapshots()
    }

    /// 启动任务自动刷新。
    /// 始终先执行一次立即刷新；当 `refreshRate` 大于 0 时再启动周期轮询。
    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        let refreshInterval = Self.configuredTaskRefreshInterval()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            // Initial fetch
            await self.refreshData()

            guard let refreshInterval else { return }
            let intervalNanos = UInt64(refreshInterval * 1_000_000_000)

            // Periodic fetch
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }

                // Completely freeze refresh while user is scrolling a major surface.
                let isRefreshSuspended = await MainActor.run {
                    self.isRefreshSuspendedForScrolling
                }
                guard !isRefreshSuspended else { continue }

                let remainingCooldown = await MainActor.run {
                    self.remainingRefreshSuspensionCooldownNanoseconds()
                }
                if remainingCooldown > 0 {
                    try? await Task.sleep(nanoseconds: remainingCooldown)
                    guard !Task.isCancelled else { break }

                    let isStillRefreshSuspended = await MainActor.run {
                        self.isRefreshSuspendedForScrolling
                    }
                    guard !isStillRefreshSuspended else { continue }
                }
                await self.refreshData(isSilent: true)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// 刷新所有服务器的任务 (对应 User Request: refreshData)
    func refreshData(isSilent: Bool = false) async {
        let shouldPublishLoadingState = !isSilent

        if shouldPublishLoadingState {
            await MainActor.run {
                refreshDataInFlightCount += 1
                isRefreshingTasks = true
            }
        }
        defer {
            if shouldPublishLoadingState {
                Task { @MainActor in
                    self.refreshDataInFlightCount = max(0, self.refreshDataInFlightCount - 1)
                    self.isRefreshingTasks = self.refreshDataInFlightCount > 0
                }
            }
        }

        var processedServerPayloads: [ProcessedServerTasks] = []
        var aggregatedDownloadSpeed: Int64 = 0
        var aggregatedUploadSpeed: Int64 = 0
        var aggregatedDownloadingCount = 0
        var aggregatedSeedingCount = 0
        var aggregatedSeedingSize: Int64 = 0
        var aggregatedHasRecentFinishedTasks = false
        var aggregatedHasRecentFinishedByServerID: [UUID: Bool] = [:]
        var aggregatedSpeedByServerID: [UUID: ServerSpeedTotals] = [:]
        var aggregatedSeedingByServerID: [UUID: ServerSeedingTotals] = [:]
        var serverRefreshMutations: [ServerRefreshMutation] = []
        aggregatedSpeedByServerID.reserveCapacity(max(servers.count, 1))
        aggregatedSeedingByServerID.reserveCapacity(max(servers.count, 1))
        aggregatedHasRecentFinishedByServerID.reserveCapacity(max(servers.count, 1))
        serverRefreshMutations.reserveCapacity(max(servers.count, 1))

        func ingestServerTasks(_ processed: ProcessedServerTasks, for server: ServerConfig) {
            processedServerPayloads.append(processed)

            let serverStats = processed.stats
            aggregatedDownloadSpeed += serverStats.totalDownloadSpeed
            aggregatedUploadSpeed += serverStats.totalUploadSpeed
            aggregatedDownloadingCount += serverStats.downloadingCount
            aggregatedSeedingCount += serverStats.seedingCount
            aggregatedSeedingSize += serverStats.seedingSize
            if serverStats.hasRecentFinishedTask {
                aggregatedHasRecentFinishedTasks = true
            }
            aggregatedHasRecentFinishedByServerID[server.id] = serverStats.hasRecentFinishedTask
            aggregatedSpeedByServerID[server.id] = ServerSpeedTotals(
                download: serverStats.totalDownloadSpeed,
                upload: serverStats.totalUploadSpeed
            )
            aggregatedSeedingByServerID[server.id] = ServerSeedingTotals(
                count: serverStats.seedingCount,
                size: serverStats.seedingSize
            )
            serverRefreshMutations.append(
                ServerRefreshMutation(
                    serverID: server.id,
                    connectivity: .success,
                    stats: serverStats
                )
            )
        }

        // Parallel fetching could be done with TaskGroup, but for now serial is safer for debug
        for server in servers {
            let client = getClient(for: server)
            await MainActor.run {
                markServerPending(server, isSilent: isSilent)
            }
            do {
                // Try fetch
                let tasks = try await client.fetchTorrents()
                let processed = await Self.processFetchedTasks(tasks)
                ingestServerTasks(processed, for: server)
            } catch let error as TorrentClientError {
                // If auth failed, try login and retry
                if case .authenticationFailed = error {
                    do {
                        try await client.login()
                        let tasks = try await client.fetchTorrents()
                        let processed = await Self.processFetchedTasks(tasks)
                        ingestServerTasks(processed, for: server)
                    } catch {
                        if isBenignCancellationError(error) {
                            continue
                        } else {
                            print("Auth retry failed for \(server.name): \(error)")
                            serverRefreshMutations.append(
                                ServerRefreshMutation(
                                    serverID: server.id,
                                    connectivity: .failure,
                                    stats: nil
                                )
                            )
                        }
                    }
                } else {
                    print("Fetch failed for \(server.name): \(error)")
                    serverRefreshMutations.append(
                        ServerRefreshMutation(
                            serverID: server.id,
                            connectivity: .failure,
                            stats: nil
                        )
                    )
                }
            } catch {
                if isBenignCancellationError(error) {
                    continue
                }
                print("Unknown error for \(server.name): \(error)")
                serverRefreshMutations.append(
                    ServerRefreshMutation(
                        serverID: server.id,
                        connectivity: .failure,
                        stats: nil
                    )
                )
            }
        }

        let finalHasRecentFinished = aggregatedHasRecentFinishedTasks
        let finalHasRecentByServer = aggregatedHasRecentFinishedByServerID
        let activeServerIDSnapshot = await MainActor.run { self.activeServerId }
        let taskRefreshSnapshot = await Self.makeTaskRefreshSnapshot(
            from: processedServerPayloads,
            activeServerID: activeServerIDSnapshot,
            hasRecentFinishedAll: finalHasRecentFinished,
            hasRecentFinishedByServerID: finalHasRecentByServer,
            serverRefreshMutations: serverRefreshMutations,
            aggregatedDownloadingCount: aggregatedDownloadingCount,
            aggregatedDownloadSpeed: aggregatedDownloadSpeed,
            aggregatedUploadSpeed: aggregatedUploadSpeed,
            aggregatedSeedingCount: aggregatedSeedingCount,
            aggregatedSeedingSize: aggregatedSeedingSize,
            aggregatedSpeedByServerID: aggregatedSpeedByServerID,
            aggregatedSeedingByServerID: aggregatedSeedingByServerID,
            publicationDate: Date()
        )
        await MainActor.run {
            self.enqueueTaskRefreshSnapshot(taskRefreshSnapshot)
        }
    }

    @MainActor
    private func schedulePendingTaskRefreshPublication(minimumDelay: UInt64) {
        let delay = max(minimumDelay, remainingRefreshSuspensionCooldownNanoseconds())
        taskRefreshPublicationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.publishPendingTaskRefreshSnapshot()
        }
    }

    @MainActor
    func remainingRefreshSuspensionCooldownNanoseconds() -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard refreshSuspensionCooldownDeadline > now else { return 0 }
        return refreshSuspensionCooldownDeadline - now
    }

    @MainActor
    func checkServerStatus() {
        for server in servers {
            let client = getClient(for: server)
            markServerPending(server, isSilent: false)

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
    private func markServerPending(_ server: ServerConfig, isSilent: Bool) {
        server.beginConnectionRefresh(isSilent: isSilent)
    }

    @MainActor
    private func markServerOnline(_ server: ServerConfig) {
        server.registerConnectionSuccess()
    }

    @MainActor
    private func markServerFailure(_ server: ServerConfig) {
        server.registerConnectionFailure()
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

    @MainActor
    private func applyServerTaskStats(_ stats: ServerTaskStats, to server: ServerConfig) {
        server.totalSeedingCount = stats.seedingCount
        server.totalDownloadingCount = stats.downloadingCount
        server.totalSeedingSize = stats.seedingSize
        server.totalRatio = stats.totalDownloaded > 0
            ? Double(stats.totalUploaded) / Double(stats.totalDownloaded)
            : 0.0
    }

    func availableCategoryOptions(for task: TorrentTask) -> [String] {
        availableCategoryOptions(for: Set([task]))
    }

    func availableCategoryOptions(for tasks: Set<TorrentTask>) -> [String] {
        let serverIDs = Set(tasks.map(\.serverID))
        let currentCategories = tasks.map(\.category)
        return mergedCategoryOptions(for: serverIDs, including: currentCategories)
    }

    func availableTagOptions(for task: TorrentTask) -> [String] {
        availableTagOptions(for: Set([task]))
    }

    func availableTagOptions(for tasks: Set<TorrentTask>) -> [String] {
        let serverIDs = Set(tasks.map(\.serverID))
        let currentTags = tasks.flatMap { Array(normalizedTagSet(from: $0.tags)) }
        return mergedTagOptions(for: serverIDs, including: currentTags)
    }

    @MainActor
    func prewarmTaxonomyIfNeeded(for task: TorrentTask) {
        prewarmTaxonomyIfNeeded(for: Set([task]))
    }

    @MainActor
    func prewarmTaxonomyIfNeeded(for tasks: Set<TorrentTask>) {
        prewarmTaxonomyIfNeeded(forServerIDs: Set(tasks.map(\.serverID)))
    }

    @MainActor
    private func ingestTaskDerivedTaxonomy(categories: [String], tags: [String], for server: ServerConfig) {
        var didChange = false
        if taskDerivedCategoriesByServerID[server.id] != categories {
            taskDerivedCategoriesByServerID[server.id] = categories
            didChange = true
        }
        if taskDerivedTagsByServerID[server.id] != tags {
            taskDerivedTagsByServerID[server.id] = tags
            didChange = true
        }

        if didChange {
            refreshAvailableTaxonomySnapshots()
        }
    }

    @MainActor
    private func prewarmTaxonomyIfNeeded(for serverID: UUID) {
        prewarmTaxonomyIfNeeded(forServerIDs: Set([serverID]))
    }

    @MainActor
    private func prewarmTaxonomyIfNeeded(forServerIDs serverIDs: Set<UUID>) {
        for serverID in serverIDs {
            guard let server = servers.first(where: { $0.id == serverID }) else { continue }

            let supportsCategories = server.type == .qBittorrent
            let supportsTags = server.type == .qBittorrent || server.type == .transmission
            guard supportsCategories || supportsTags else { continue }

            if taxonomyWarmupTasksByServerID[serverID] != nil {
                continue
            }

            if let lastWarmup = taxonomyWarmupDatesByServerID[serverID],
               Date().timeIntervalSince(lastWarmup) < taxonomyWarmupTTL {
                continue
            }

            taxonomyWarmupTasksByServerID[serverID] = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.taxonomyWarmupTasksByServerID[serverID] = nil
                }

                do {
                    if supportsCategories {
                        _ = try await self.fetchServerCategories(for: server)
                    }
                    if supportsTags {
                        _ = try await self.fetchServerTags(for: server)
                    }
                    self.taxonomyWarmupDatesByServerID[serverID] = Date()
                } catch {
                    self.taxonomyWarmupDatesByServerID[serverID] = Date()
                    print("Taxonomy prewarm failed for \(server.name): \(error)")
                }
            }
        }
    }

    @MainActor
    private func storeServerCategories(_ categories: [String], for serverID: UUID) {
        if serverCategoriesByServerID[serverID] != categories {
            serverCategoriesByServerID[serverID] = categories
            refreshAvailableTaxonomySnapshots()
        }
    }

    @MainActor
    private func storeServerTags(_ tags: [String], for serverID: UUID) {
        if serverTagsByServerID[serverID] != tags {
            serverTagsByServerID[serverID] = tags
            refreshAvailableTaxonomySnapshots()
        }
    }

    @MainActor
    private func invalidateTaxonomyWarmup(for serverID: UUID) {
        taxonomyWarmupDatesByServerID[serverID] = nil
    }

    @MainActor
    private func refreshAvailableTaxonomySnapshots() {
        let mergedCategories = Self.sortedUniqueValues(
            taskDerivedCategoriesByServerID.values.flatMap { $0 } +
            serverCategoriesByServerID.values.flatMap { $0 }
        )
        let mergedTags = Self.sortedUniqueValues(
            taskDerivedTagsByServerID.values.flatMap { $0 } +
            serverTagsByServerID.values.flatMap { $0 }
        )

        if availableCategories != mergedCategories {
            availableCategories = mergedCategories
        }
        if availableTags != mergedTags {
            availableTags = mergedTags
        }
    }

    private func mergedCategoryOptions(for serverIDs: Set<UUID>, including currentCategories: [String]) -> [String] {
        let cached = serverIDs.flatMap { serverID in
            (taskDerivedCategoriesByServerID[serverID] ?? []) +
            (serverCategoriesByServerID[serverID] ?? [])
        }
        return Self.sortedUniqueValues(cached + currentCategories)
    }

    private func mergedTagOptions(for serverIDs: Set<UUID>, including currentTags: [String]) -> [String] {
        let cached = serverIDs.flatMap { serverID in
            (taskDerivedTagsByServerID[serverID] ?? []) +
            (serverTagsByServerID[serverID] ?? [])
        }
        return Self.sortedUniqueValues(cached + currentTags)
    }

    nonisolated private static func processFetchedTasks(_ tasks: [TorrentTask]) async -> ProcessedServerTasks {
        await Task.detached(priority: .userInitiated) {
            ProcessedServerTasks(tasks: tasks, stats: Self.buildServerTaskStats(from: tasks))
        }.value
    }

    nonisolated private static func makeTaskRefreshSnapshot(
        from payloads: [ProcessedServerTasks],
        activeServerID: UUID?,
        hasRecentFinishedAll: Bool,
        hasRecentFinishedByServerID: [UUID: Bool],
        serverRefreshMutations: [ServerRefreshMutation],
        aggregatedDownloadingCount: Int,
        aggregatedDownloadSpeed: Int64,
        aggregatedUploadSpeed: Int64,
        aggregatedSeedingCount: Int,
        aggregatedSeedingSize: Int64,
        aggregatedSpeedByServerID: [UUID: ServerSpeedTotals],
        aggregatedSeedingByServerID: [UUID: ServerSeedingTotals],
        publicationDate: Date
    ) async -> TaskRefreshSnapshot {
        await Task.detached(priority: .userInitiated) {
            let allTasks = payloads.flatMap(\.tasks)
            // Compute a cheap O(n) fingerprint here on a background thread,
            // so the main thread publish step can skip the O(n) equality check entirely.
            var hash = allTasks.count
            if let first = allTasks.first { hash ^= first.id.hashValue }
            if let last = allTasks.last { hash ^= last.id.hashValue &* 0x9e3779b9 }
            hash ^= allTasks.count &* 2654435761
            return TaskRefreshSnapshot(
                allTasks: allTasks,
                displayedTasks: Self.makeDisplayedTasks(from: allTasks, activeServerID: activeServerID),
                activeServerID: activeServerID,
                hasRecentFinishedAll: hasRecentFinishedAll,
                hasRecentFinishedByServerID: hasRecentFinishedByServerID,
                serverRefreshMutations: serverRefreshMutations,
                aggregatedDownloadingCount: aggregatedDownloadingCount,
                aggregatedDownloadSpeed: aggregatedDownloadSpeed,
                aggregatedUploadSpeed: aggregatedUploadSpeed,
                aggregatedSeedingCount: aggregatedSeedingCount,
                aggregatedSeedingSize: aggregatedSeedingSize,
                aggregatedSpeedByServerID: aggregatedSpeedByServerID,
                aggregatedSeedingByServerID: aggregatedSeedingByServerID,
                publicationDate: publicationDate,
                allTasksHash: hash
            )
        }.value
    }

    nonisolated private static func buildServerTaskStats(from tasks: [TorrentTask]) -> ServerTaskStats {
        var seedingCount = 0
        var downloadingCount = 0
        var seedingSize: Int64 = 0
        var totalUploaded: Int64 = 0
        var totalDownloaded: Int64 = 0
        var totalDownloadSpeed: Int64 = 0
        var totalUploadSpeed: Int64 = 0
        var hasRecentFinishedTask = false
        var categories = Set<String>()
        var tags = Set<String>()
        categories.reserveCapacity(min(tasks.count, 512))
        tags.reserveCapacity(min(tasks.count * 2, 2048))

        for task in tasks {
            if task.status == .seeding {
                seedingCount += 1
                seedingSize += task.size
            } else if task.status == .downloading {
                downloadingCount += 1
            }

            totalUploaded += task.uploaded
            totalDownloaded += task.downloaded
            totalDownloadSpeed += task.downloadSpeed
            totalUploadSpeed += task.uploadSpeed

            if !hasRecentFinishedTask &&
                (task.status == .completed || task.status == .seeding || task.completionDate != nil || task.progress >= 0.999) {
                hasRecentFinishedTask = true
            }

            let category = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !category.isEmpty {
                categories.insert(category)
            }

            if !task.normalizedTags.isEmpty {
                tags.formUnion(task.normalizedTags)
            }
        }

        return ServerTaskStats(
            seedingCount: seedingCount,
            downloadingCount: downloadingCount,
            seedingSize: seedingSize,
            totalUploaded: totalUploaded,
            totalDownloaded: totalDownloaded,
            totalDownloadSpeed: totalDownloadSpeed,
            totalUploadSpeed: totalUploadSpeed,
            hasRecentFinishedTask: hasRecentFinishedTask,
            derivedCategories: Self.sortedUniqueValues(Array(categories)),
            derivedTags: Self.sortedUniqueValues(Array(tags))
        )
    }

    // MARK: - Server Category / Tag Settings

    func fetchServerCategories(for server: ServerConfig) async throws -> [QBittorrentClient.ServerCategoryEntry] {
        guard server.type == .qBittorrent else { return [] }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        let categories = try await client.fetchServerCategories()
        let normalized = Self.sortedUniqueValues(categories.map(\.name))
        await MainActor.run {
            storeServerCategories(normalized, for: server.id)
        }
        return categories
    }

    func createServerCategory(for server: ServerConfig, name: String, savePath: String) async throws {
        guard server.type == .qBittorrent else {
            throw TorrentClientError.apiError("Current server does not support categories.")
        }
        guard let client = getClient(for: server) as? QBittorrentClient else {
            throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
        }
        try await client.createServerCategory(name: name, savePath: savePath)
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
        }
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
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
        }
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
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
        }
        await refreshData()
    }

    func fetchServerTags(for server: ServerConfig) async throws -> [String] {
        let tags: [String]
        switch server.type {
        case .qBittorrent:
            guard let client = getClient(for: server) as? QBittorrentClient else {
                throw TorrentClientError.apiError("Failed to initialize qBittorrent client.")
            }
            tags = try await client.fetchServerTags()
        case .transmission:
            guard let client = getClient(for: server) as? TransmissionClient else {
                throw TorrentClientError.apiError("Failed to initialize Transmission client.")
            }
            tags = try await client.fetchServerTags()
        }
        let normalized = Self.sortedUniqueValues(tags)
        await MainActor.run {
            storeServerTags(normalized, for: server.id)
        }
        return tags
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
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
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
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
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
        await MainActor.run {
            invalidateTaxonomyWarmup(for: server.id)
        }
        await refreshData()
    }

    // MARK: - Task Category / Tag Actions

    func fetchTaskCategoryOptions(for task: TorrentTask) async throws -> [String] {
        try await fetchTaskCategoryOptions(for: Set([task]))
    }

    func fetchTaskCategoryOptions(for tasks: Set<TorrentTask>) async throws -> [String] {
        await MainActor.run {
            prewarmTaxonomyIfNeeded(for: tasks)
        }
        return await MainActor.run {
            availableCategoryOptions(for: tasks)
        }
    }

    func fetchTaskTagOptions(for task: TorrentTask) async throws -> [String] {
        try await fetchTaskTagOptions(for: Set([task]))
    }

    func fetchTaskTagOptions(for tasks: Set<TorrentTask>) async throws -> [String] {
        await MainActor.run {
            prewarmTaxonomyIfNeeded(for: tasks)
        }
        return await MainActor.run {
            availableTagOptions(for: tasks)
        }
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
                    let currentTagSet = Set(task.normalizedTags)
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
        let trimmed = newTrackers.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        performTaskAction(task) { client, id in
            try await client.editTrackers(hash: id, newTrackers: trimmed)
            await self.refreshData()
        }
    }

    // MARK: - Per-Torrent Speed Limits

    /// Fetch current per-torrent speed limits in KB/s. Returns (dlKBps, upKBps); 0 means unlimited.
    func fetchTorrentSpeedLimits(for task: TorrentTask) async throws -> (dlKBps: Int, upKBps: Int) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }
        let client = getClient(for: server)

        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            let limits = try await qbClient.fetchTorrentSpeedLimits(hash: task.hash)
            // qBittorrent returns Bytes/s → convert to KB/s
            return (dlKBps: limits.dlLimit / 1024, upKBps: limits.upLimit / 1024)

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            let limits = try await trClient.fetchTorrentSpeedLimits(hash: task.hash)
            // Transmission returns KB/s; 0 if not limited
            return (
                dlKBps: limits.dlLimited ? limits.dlLimit : 0,
                upKBps: limits.upLimited ? limits.upLimit : 0
            )
        }
    }

    /// Set per-torrent speed limits in KB/s. Pass 0 to remove the limit.
    func setTorrentSpeedLimits(for task: TorrentTask, dlKBps: Int, upKBps: Int) async throws {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }
        let client = getClient(for: server)

        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            // KB/s → Bytes/s
            try await qbClient.setTorrentSpeedLimits(
                hash: task.hash,
                dlLimitBytesPerSec: dlKBps * 1024,
                upLimitBytesPerSec: upKBps * 1024
            )

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            try await trClient.setTorrentSpeedLimits(
                hash: task.hash,
                dlLimitKBps: dlKBps,
                dlLimited: dlKBps > 0,
                upLimitKBps: upKBps,
                upLimited: upKBps > 0
            )
        }
    }

    // MARK: - Server Connection Settings

    func fetchConnectionSettings(for server: ServerConfig) async throws -> ConnectionSettings {
        let client = getClient(for: server)

        do {
            return try await client.getConnectionSettings()
        } catch let error as TorrentClientError {
            if case .authenticationFailed = error {
                try await client.login()
                return try await client.getConnectionSettings()
            }
            throw error
        } catch {
            throw error
        }
    }

    func saveConnectionSettings(_ settings: ConnectionSettings, for server: ServerConfig) async throws {
        let client = getClient(for: server)

        do {
            try await client.setConnectionSettings(settings)
        } catch let error as TorrentClientError {
            if case .authenticationFailed = error {
                try await client.login()
                try await client.setConnectionSettings(settings)
                return
            }
            throw error
        } catch {
            throw error
        }
    }

    func fetchDownloadSettings(for server: ServerConfig) async throws -> DownloadSettings {
        let client = getClient(for: server)

        do {
            return try await client.getDownloadSettings()
        } catch let error as TorrentClientError {
            if case .authenticationFailed = error {
                try await client.login()
                return try await client.getDownloadSettings()
            }
            throw error
        } catch {
            throw error
        }
    }

    func saveDownloadSettings(_ settings: DownloadSettings, for server: ServerConfig) async throws {
        let client = getClient(for: server)

        do {
            try await client.setDownloadSettings(settings)
        } catch let error as TorrentClientError {
            if case .authenticationFailed = error {
                try await client.login()
                try await client.setDownloadSettings(settings)
                return
            }
            throw error
        } catch {
            throw error
        }
    }

    // MARK: - Tracker Management

    func fetchTrackers(for task: TorrentTask) async throws -> [TorrentTrackerInfo] {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }

        let client = getClient(for: server)

        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }

            do {
                return try await qbClient.fetchTrackers(hash: task.hash)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await qbClient.login()
                    return try await qbClient.fetchTrackers(hash: task.hash)
                }
                throw error
            } catch {
                throw error
            }

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }

            do {
                return try await trClient.fetchTrackers(hash: task.hash)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await trClient.login()
                    return try await trClient.fetchTrackers(hash: task.hash)
                }
                throw error
            } catch {
                throw error
            }
        }
    }

    // MARK: - Peer Management

    func fetchPeers(for task: TorrentTask) async throws -> [TorrentPeerInfo] {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }

        let client = getClient(for: server)

        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }

            do {
                return try await qbClient.fetchPeers(hash: task.hash)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await qbClient.login()
                    return try await qbClient.fetchPeers(hash: task.hash)
                }
                throw error
            } catch {
                throw error
            }

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }

            do {
                return try await trClient.fetchPeers(hash: task.hash)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await trClient.login()
                    return try await trClient.fetchPeers(hash: task.hash)
                }
                throw error
            } catch {
                throw error
            }
        }
    }

    func addPeers(for task: TorrentTask, peers: [String]) async throws {
        let normalizedPeers = peers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedPeers.isEmpty else { return }

        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }

        let client = getClient(for: server)
        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            do {
                try await qbClient.addPeers(hash: task.hash, peers: normalizedPeers)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await qbClient.login()
                    try await qbClient.addPeers(hash: task.hash, peers: normalizedPeers)
                    return
                }
                throw error
            }

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            do {
                try await trClient.addPeers(hash: task.hash, peers: normalizedPeers)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await trClient.login()
                    try await trClient.addPeers(hash: task.hash, peers: normalizedPeers)
                    return
                }
                throw error
            }
        }
    }

    func banPeers(for task: TorrentTask, peers: [String]) async throws {
        let normalizedPeers = peers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedPeers.isEmpty else { return }

        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }

        let client = getClient(for: server)
        switch server.type {
        case .qBittorrent:
            guard let qbClient = client as? QBittorrentClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            do {
                try await qbClient.banPeers(normalizedPeers)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await qbClient.login()
                    try await qbClient.banPeers(normalizedPeers)
                    return
                }
                throw error
            }

        case .transmission:
            guard let trClient = client as? TransmissionClient else {
                throw TorrentClientError.apiError("Invalid client type")
            }
            do {
                try await trClient.banPeers(normalizedPeers)
            } catch let error as TorrentClientError {
                if case .authenticationFailed = error {
                    try await trClient.login()
                    try await trClient.banPeers(normalizedPeers)
                    return
                }
                throw error
            }
        }
    }

    // MARK: - File Management

    func fetchFiles(for task: TorrentTask) async throws -> [TorrentFile] {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }
        let client = getClient(for: server)
        try await client.login()
        return try await client.getFiles(hash: task.hash)
    }

    func setFilePriority(for task: TorrentTask, fileIndices: [Int], priority: FilePriority) async throws {
        guard let server = servers.first(where: { $0.id == task.serverID }) else {
            throw TorrentClientError.apiError("Server not found")
        }
        let client = getClient(for: server)
        try await client.login()
        try await client.setFilePriority(hash: task.hash, fileIndices: fileIndices, priority: priority)
    }

    // MARK: - Batch Actions

    /// Chunk size for background silent queue.
    private static let batchChunkSize = 500
    private static let refreshSuspensionCooldownNanos: UInt64 = 900_000_000

    /// Unified bulk action engine with O(1) select-all, optimistic UI, and background chunked queue.
    ///
    /// - Parameters:
    ///   - hashes: Raw hash strings from selected items (the `TorrentTask.hash` values, not composite IDs).
    ///   - serverID: The server these hashes belong to (single-server scope).
    ///   - isSelectAll: When `true`, sends a single `"all"` request instead of iterating hashes.
    ///   - optimisticMutation: Optional closure that instantly mutates `allTasks` on `@MainActor` for immediate UI feedback.
    ///   - perClientAction: The actual API call. Receives the client and either `"all"` or a pipe/array-ready chunk.
    @MainActor private func performBulkAction(
        hashes: [String],
        serverID: UUID?,
        isSelectAll: Bool,
        optimisticMutation: ((_ tasks: inout [TorrentTask]) -> Void)?,
        perClientAction: @escaping (TorrentClient, [String]) async throws -> Void
    ) {
        guard !hashes.isEmpty || isSelectAll else { return }

        // 1. Optimistic UI update — instant visual feedback on @MainActor
        if let mutation = optimisticMutation {
            mutation(&self.allTasks)
            rebuildDisplayedTasks()
            self.tasksRevision += 1
        }

        // 2. Capture values for detached task
        let capturedServers = self.servers
        let capturedManager = self
        let chunkSize = Self.batchChunkSize

        // 3. Background silent chunked queue — fully detached from view lifecycle
        Task.detached(priority: .background) {
            do {
                if isSelectAll {
                    // O(1) select-all path: one request per server
                    if let sid = serverID {
                        guard let server = capturedServers.first(where: { $0.id == sid }) else { return }
                        let client = await capturedManager.getClient(for: server)
                        try await perClientAction(client, ["all"])
                    } else {
                        // All-servers mode
                        for server in capturedServers {
                            let client = await capturedManager.getClient(for: server)
                            try await perClientAction(client, ["all"])
                        }
                    }
                } else {
                    // Group hashes by server and chunk
                    // For single-server scope, all hashes go to one server
                    if let sid = serverID {
                        guard let server = capturedServers.first(where: { $0.id == sid }) else { return }
                        let client = await capturedManager.getClient(for: server)
                        let chunks = hashes.chunked(into: chunkSize)
                        for chunk in chunks {
                            try await perClientAction(client, chunk)
                            if chunks.count > 1 {
                                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s debounce
                            }
                        }
                    } else {
                        // Multi-server: need to resolve which hash belongs where via allTasks snapshot
                        let tasksSnapshot = await capturedManager.allTasks
                        let hashSet = Set(hashes)
                        let grouped = Dictionary(grouping: tasksSnapshot.filter { hashSet.contains($0.hash) }, by: \.serverID)

                        for (sID, serverTasks) in grouped {
                            guard let server = capturedServers.first(where: { $0.id == sID }) else { continue }
                            let client = await capturedManager.getClient(for: server)
                            let serverHashes = serverTasks.map(\.hash)
                            let chunks = serverHashes.chunked(into: chunkSize)
                            for chunk in chunks {
                                try await perClientAction(client, chunk)
                                if chunks.count > 1 {
                                    try await Task.sleep(nanoseconds: 100_000_000)
                                }
                            }
                        }
                    }
                }
            } catch {
                print("[SeedPilot] Batch action error: \(error)")
            }

            // 4. Reconciliation: silent data refresh to align with server truth
            await capturedManager.refreshData()
        }
    }

    // MARK: - Public Batch Methods (with Optimistic UI)

    func pauseTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool) {
        let hashSet = Set(hashes)
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: { tasks in
                for i in tasks.indices where hashSet.contains(tasks[i].hash) || isSelectAll {
                    if tasks[i].status != .paused {
                        tasks[i] = Self.taskWithStatus(tasks[i], newStatus: .paused)
                    }
                }
            },
            perClientAction: { client, chunk in
                try await client.pauseTasks(hashes: chunk)
            }
        )
    }

    func resumeTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool) {
        let hashSet = Set(hashes)
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: { tasks in
                for i in tasks.indices where hashSet.contains(tasks[i].hash) || isSelectAll {
                    if tasks[i].status == .paused {
                        tasks[i] = Self.taskWithStatus(tasks[i], newStatus: .downloading)
                    }
                }
            },
            perClientAction: { client, chunk in
                try await client.resumeTasks(hashes: chunk)
            }
        )
    }

    func deleteTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool, withData: Bool) {
        let hashSet = Set(hashes)
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: { tasks in
                if isSelectAll {
                    tasks.removeAll()
                } else {
                    tasks.removeAll { hashSet.contains($0.hash) }
                }
            },
            perClientAction: { client, chunk in
                try await client.deleteTasks(hashes: chunk, withData: withData)
            }
        )
    }

    func forceStartTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool) {
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: nil,
            perClientAction: { client, chunk in
                try await client.forceStartTasks(hashes: chunk)
            }
        )
    }

    func recheckTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool) {
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: nil,
            perClientAction: { client, chunk in
                try await client.recheckTasks(hashes: chunk)
            }
        )
    }

    func reannounceTasks(hashes: [String], serverID: UUID?, isSelectAll: Bool) {
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: nil,
            perClientAction: { client, chunk in
                try await client.reannounceTasks(hashes: chunk)
            }
        )
    }

    func setTransferLocationBatch(hashes: [String], serverID: UUID?, isSelectAll: Bool, newLocation: String) {
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: nil,
            perClientAction: { client, chunk in
                for hash in chunk {
                    try await client.setLocation(hash: hash, newLocation: newLocation)
                }
            }
        )
    }

    func editTrackersBatch(hashes: [String], serverID: UUID?, isSelectAll: Bool, newTrackers: String) {
        let trimmed = newTrackers.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        performBulkAction(
            hashes: hashes,
            serverID: serverID,
            isSelectAll: isSelectAll,
            optimisticMutation: nil,
            perClientAction: { client, chunk in
                for hash in chunk {
                    try await client.editTrackers(hash: hash, newTrackers: trimmed)
                }
            }
        )
    }

    /// Helper: create a copy of a TorrentTask with a different status.
    private static func taskWithStatus(_ task: TorrentTask, newStatus: TorrentStatus) -> TorrentTask {
        TorrentTask(
            hash: task.hash,
            name: task.name,
            progress: task.progress,
            size: task.size,
            downloadSpeed: newStatus == .paused ? 0 : task.downloadSpeed,
            uploadSpeed: newStatus == .paused ? 0 : task.uploadSpeed,
            remainingTime: task.remainingTime,
            status: newStatus,
            errorCode: task.errorCode,
            errorMessage: task.errorMessage,
            serverID: task.serverID,
            tracker: task.tracker,
            savePath: task.savePath,
            category: task.category,
            tags: task.tags,
            downloaded: task.downloaded,
            uploaded: task.uploaded,
            isSequential: task.isSequential,
            isFirstLastPiecePriority: task.isFirstLastPiecePriority,
            completionDate: task.completionDate,
            seedingTime: task.seedingTime,
            addedTime: task.addedTime,
            resolutionBadge: task.resolutionBadge,
            displayText: task.displayText,
            numSeeds: task.numSeeds,
            totalSeeds: task.totalSeeds,
            numPeers: task.numPeers,
            totalPeers: task.totalPeers,
            ratio: task.ratio,
            normalizedTags: task.normalizedTags
        )
    }

    // MARK: - Legacy Compatibility (single-task actions unchanged)

    private func performTaskAction(_ task: TorrentTask, action: @escaping (TorrentClient, String) async throws -> Void) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)
        Task {
            do {
                try await action(client, task.hash)
            } catch {
                print("Task action failed: \(error)")
            }
        }
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        Self.sortedUniqueValues(tags)
    }

    private func normalizedTagSet(from raw: String) -> Set<String> {
        Set(
            raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    nonisolated private static func sortedUniqueValues(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isBenignCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
