//
//  DashboardViewModel.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Combine
import SwiftUI

struct TrackerTransferData: Identifiable {
    let id: String
    let trackerName: String
    let bytes: Int64
    let color: Color
}

private struct TrackerTransferAggregate: Sendable {
    let trackerName: String
    let uploadedBytes: Int64
    let downloadedBytes: Int64
}

private nonisolated struct TrackerTransferBaselineEntry: Codable, Sendable, Equatable {
    let uploaded: Int64
    let downloaded: Int64
    let latestUploaded: Int64?
    let latestDownloaded: Int64?
    let trackerName: String?
}

private nonisolated struct TrackerTransferBaselineSnapshot: Codable, Sendable {
    let tasks: [String: TrackerTransferBaselineEntry]
    let archivedByTracker: [String: TrackerTransferBaselineEntry]?
}

private struct TrackerTransferBreakdownResult: Sendable {
    let uploadData: [TrackerTransferData]
    let downloadData: [TrackerTransferData]
    let baselineSnapshot: TrackerTransferBaselineSnapshot
    let encodedBaselineSnapshotData: Data
}

private struct DashboardServerRuntimeInput: Sendable {
    let id: UUID
    let name: String
    let connectionState: ServerConnectionState
    let isOnline: Bool?
    let totalSeedingCount: Int
    let totalDownloadingCount: Int
}

private struct DashboardGlobalStatsMergeResult: Sendable {
    let snapshot: GlobalStatsSnapshot
    let updatedStorageByServer: [UUID: DashboardServerStorageEntry]
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var globalSnapshot = GlobalStatsSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUsingCachedFallback = false
    @Published private(set) var hasLoadedInitialSnapshot = false
    @Published private(set) var moduleOrder: [DashboardModuleType] = DashboardModuleType.defaultOrder
    @Published private(set) var recentUploadBytes: Int64 = 0
    @Published private(set) var recentDownloadBytes: Int64 = 0
    @Published private(set) var recentUploadData: [TrackerTransferData] = []
    @Published private(set) var recentDownloadData: [TrackerTransferData] = []
    @Published private(set) var isTransferStatsLoading = false
    @Published private(set) var hasTransferStatsLoadedAtLeastOnce = false

    @AppStorage(DashboardConfig.Keys.moduleOrder) private var moduleOrderStorageData: Data = Data()
    @AppStorage("dashboard.transferTrackerBaselineSnapshot") private var trackerTransferBaselineSnapshotData: Data = Data()
    private let statsManager: GlobalStatsManager
    private var autoRefreshTask: Task<Void, Never>?
    private var lastSuccessfulSnapshot: GlobalStatsSnapshot?
    private var lastKnownStorageByServer: [UUID: DashboardServerStorageEntry] = [:]
    private var trackerTransferBaselineSnapshotCache: TrackerTransferBaselineSnapshot?

    private var baselineDL: Int64 {
        get {
            guard let number = UserDefaults.standard.object(forKey: Self.baselineDownloadKey) as? NSNumber else {
                return -1
            }
            return number.int64Value
        }
        set {
            UserDefaults.standard.set(NSNumber(value: newValue), forKey: Self.baselineDownloadKey)
        }
    }

    private var baselineUL: Int64 {
        get {
            guard let number = UserDefaults.standard.object(forKey: Self.baselineUploadKey) as? NSNumber else {
                return -1
            }
            return number.int64Value
        }
        set {
            UserDefaults.standard.set(NSNumber(value: newValue), forKey: Self.baselineUploadKey)
        }
    }

    private var baselineTimestamp: Double {
        get {
            guard let number = UserDefaults.standard.object(forKey: Self.baselineTimestampKey) as? NSNumber else {
                return 0
            }
            return number.doubleValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.baselineTimestampKey)
        }
    }

    init(statsManager: GlobalStatsManager) {
        self.statsManager = statsManager
        hydrateModuleOrderFromStorage()
        normalizeBaselineTimestampIfNeeded()
    }

    init() {
        self.statsManager = .shared
        hydrateModuleOrderFromStorage()
        normalizeBaselineTimestampIfNeeded()
    }

    var formattedBaselineTime: String {
        Self.baselineTimeFormatter.string(
            from: Date(timeIntervalSince1970: max(baselineTimestamp, 0))
        )
    }

    func resetTransferBaseline() {
        guard globalSnapshot.hasReliableTransferTotals else { return }
        applyTransferBaseline(
            downloaded: max(globalSnapshot.totalAllTimeDownloaded, 0),
            uploaded: max(globalSnapshot.totalAllTimeUploaded, 0),
            timestamp: Date().timeIntervalSince1970
        )
    }

    func syncModuleOrder(availableModules: [DashboardModuleType]) {
        let normalized = normalizeModuleOrder(moduleOrder, availableModules: availableModules)
        guard normalized != moduleOrder else {
            persistModuleOrderIfNeeded(normalized)
            return
        }
        moduleOrder = normalized
        persistModuleOrderIfNeeded(normalized)
    }

    func swapModules(
        _ source: DashboardModuleType,
        with target: DashboardModuleType,
        availableModules: [DashboardModuleType]
    ) {
        syncModuleOrder(availableModules: availableModules)

        guard source != target,
              let sourceIndex = moduleOrder.firstIndex(of: source),
              let targetIndex = moduleOrder.firstIndex(of: target),
              sourceIndex != targetIndex else {
            return
        }

        var updatedOrder = moduleOrder
        updatedOrder.swapAt(sourceIndex, targetIndex)
        moduleOrder = updatedOrder
        persistModuleOrderIfNeeded(updatedOrder)
    }

    func startAutoRefresh(
        serversProvider: @escaping @MainActor () -> [ServerConfig],
        tasksProvider: @escaping @MainActor () -> [TorrentTask],
        interval: TimeInterval = 8
    ) {
        stopAutoRefresh()

        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            let initialServers = serversProvider()
            let initialTasks = tasksProvider()
            await self.refreshGlobalStats(servers: initialServers, tasks: initialTasks, force: true)

            let intervalNanos = UInt64(max(interval, 1) * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }
                let currentServers = serversProvider()
                let currentTasks = tasksProvider()
                await self.refreshGlobalStats(
                    servers: currentServers,
                    tasks: currentTasks,
                    isSilent: true
                )
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshGlobalStats(
        servers: [ServerConfig],
        tasks: [TorrentTask],
        force: Bool = false,
        isSilent: Bool = false
    ) async {
        guard !servers.isEmpty else {
            isRefreshing = false
            isUsingCachedFallback = false
            hasLoadedInitialSnapshot = true
            globalSnapshot = GlobalStatsSnapshot(
                totalSeedingCount: 0,
                totalDownloadingCount: 0,
                totalBandwidth: 0,
                totalRemainingSpace: 0,
                totalAllTimeDownloaded: 0,
                totalAllTimeUploaded: 0,
                onlineServerCount: 0,
                failedServerCount: 0,
                hasConnectionIssue: false,
                hasReliableTransferTotals: false,
                serverStorage: [],
                lastUpdatedAt: Date()
            )
            recentUploadBytes = 0
            recentDownloadBytes = 0
            recentUploadData = []
            recentDownloadData = []
            isTransferStatsLoading = false
            hasTransferStatsLoadedAtLeastOnce = true
            lastSuccessfulSnapshot = nil
            return
        }

        let serverInputs = Self.buildServerRuntimeInputs(from: servers)
        var cachedStorageByServer = lastKnownStorageByServer

        isRefreshing = true
        isTransferStatsLoading = !hasTransferStatsLoadedAtLeastOnce

        await statsManager.refresh(servers: servers, force: force, isSilent: isSilent)
        let apiSnapshot = statsManager.snapshot
        let latestStorageSnapshot = cachedStorageByServer
        let latestResult = await Task.detached(priority: .utility) {
            DashboardViewModel.computeMergedGlobalSnapshot(
                apiSnapshot: apiSnapshot,
                servers: serverInputs,
                tasks: tasks,
                lastKnownStorageByServer: latestStorageSnapshot
            )
        }.value
        cachedStorageByServer = latestResult.updatedStorageByServer

        let shouldRetry = latestResult.snapshot.hasConnectionIssue || latestResult.snapshot.failedServerCount > 0

        var resolvedSnapshot = latestResult.snapshot
        if shouldRetry, let retried = await retryGlobalStats(
            servers: servers,
            retryCount: 2,
            isSilent: isSilent
        ) {
            let retryStorageSnapshot = cachedStorageByServer
            let retryResult = await Task.detached(priority: .utility) {
                DashboardViewModel.computeMergedGlobalSnapshot(
                    apiSnapshot: retried,
                    servers: serverInputs,
                    tasks: tasks,
                    lastKnownStorageByServer: retryStorageSnapshot
                )
            }.value
            cachedStorageByServer = retryResult.updatedStorageByServer
            resolvedSnapshot = betterSnapshot(lhs: resolvedSnapshot, rhs: retryResult.snapshot)
        }

        let finalSnapshot: GlobalStatsSnapshot
        if resolvedSnapshot.hasConnectionIssue {
            if let cached = lastSuccessfulSnapshot {
                let fallbackStorageSnapshot = cachedStorageByServer
                let cachedResult = await Task.detached(priority: .utility) {
                    DashboardViewModel.computeMergedGlobalSnapshot(
                        apiSnapshot: cached,
                        servers: serverInputs,
                        tasks: tasks,
                        lastKnownStorageByServer: fallbackStorageSnapshot
                    )
                }.value
                cachedStorageByServer = cachedResult.updatedStorageByServer
                finalSnapshot = cachedResult.snapshot
                isUsingCachedFallback = true
            } else {
                finalSnapshot = resolvedSnapshot
                isUsingCachedFallback = false
            }
        } else {
            finalSnapshot = resolvedSnapshot
            lastSuccessfulSnapshot = resolvedSnapshot
            isUsingCachedFallback = false
        }

        globalSnapshot = finalSnapshot
        syncRecentTransferStats(from: finalSnapshot)
        await syncTrackerBreakdown(tasks: tasks, snapshot: finalSnapshot)
        lastKnownStorageByServer = cachedStorageByServer
        isRefreshing = false
        hasLoadedInitialSnapshot = true
    }

    func prefetchForLaunch(servers: [ServerConfig], tasks: [TorrentTask]) async {
        await refreshGlobalStats(servers: servers, tasks: tasks, force: true)
    }

    private func retryGlobalStats(
        servers: [ServerConfig],
        retryCount: Int,
        isSilent: Bool
    ) async -> GlobalStatsSnapshot? {
        var bestSnapshot: GlobalStatsSnapshot?

        for _ in 0..<retryCount {
            guard !Task.isCancelled else { return nil }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return nil }

            await statsManager.refresh(servers: servers, force: true, isSilent: isSilent)
            let retried = statsManager.snapshot
            if let currentBest = bestSnapshot {
                bestSnapshot = betterSnapshot(lhs: currentBest, rhs: retried)
            } else {
                bestSnapshot = retried
            }

            if !retried.hasConnectionIssue && retried.failedServerCount == 0 {
                return retried
            }
        }

        return bestSnapshot
    }

    private func betterSnapshot(lhs: GlobalStatsSnapshot, rhs: GlobalStatsSnapshot) -> GlobalStatsSnapshot {
        if rhs.onlineServerCount != lhs.onlineServerCount {
            return rhs.onlineServerCount > lhs.onlineServerCount ? rhs : lhs
        }
        if rhs.hasReliableTransferTotals != lhs.hasReliableTransferTotals {
            return rhs.hasReliableTransferTotals ? rhs : lhs
        }
        let rhsActivity = rhs.totalSeedingCount + rhs.totalDownloadingCount
        let lhsActivity = lhs.totalSeedingCount + lhs.totalDownloadingCount
        if rhsActivity != lhsActivity {
            return rhsActivity > lhsActivity ? rhs : lhs
        }
        if rhs.totalRemainingSpace != lhs.totalRemainingSpace {
            return rhs.totalRemainingSpace > lhs.totalRemainingSpace ? rhs : lhs
        }
        return rhs
    }

    private func syncRecentTransferStats(from snapshot: GlobalStatsSnapshot) {
        guard snapshot.hasReliableTransferTotals else {
            isTransferStatsLoading = !hasTransferStatsLoadedAtLeastOnce
            return
        }

        let currentAllTimeDownloaded = max(snapshot.totalAllTimeDownloaded, 0)
        let currentAllTimeUploaded = max(snapshot.totalAllTimeUploaded, 0)

        if baselineDL < 0 || baselineUL < 0 {
            applyTransferBaseline(
                downloaded: currentAllTimeDownloaded,
                uploaded: currentAllTimeUploaded,
                timestamp: Date().timeIntervalSince1970
            )
            return
        }

        // If the backend-side totals dropped, silently flatten the baseline to avoid negative UI.
        if currentAllTimeDownloaded < baselineDL || currentAllTimeUploaded < baselineUL {
            applyTransferBaseline(
                downloaded: currentAllTimeDownloaded,
                uploaded: currentAllTimeUploaded,
                timestamp: Date().timeIntervalSince1970
            )
            return
        }

        recentDownloadBytes = max(currentAllTimeDownloaded - baselineDL, 0)
        recentUploadBytes = max(currentAllTimeUploaded - baselineUL, 0)
        hasTransferStatsLoadedAtLeastOnce = true
        isTransferStatsLoading = false
    }

    private func applyTransferBaseline(downloaded: Int64, uploaded: Int64, timestamp: Double) {
        baselineDL = max(downloaded, 0)
        baselineUL = max(uploaded, 0)
        baselineTimestamp = timestamp
        recentDownloadBytes = 0
        recentUploadBytes = 0
        recentUploadData = []
        recentDownloadData = []
        trackerTransferBaselineSnapshotCache = nil
        trackerTransferBaselineSnapshotData = Data()
        hasTransferStatsLoadedAtLeastOnce = true
        isTransferStatsLoading = false
    }

    private func syncTrackerBreakdown(tasks: [TorrentTask], snapshot: GlobalStatsSnapshot) async {
        guard snapshot.hasReliableTransferTotals else { return }

        let baselineSnapshot = trackerTransferBaselineSnapshotCache
            ?? Self.decodeTrackerBaselineSnapshot(from: trackerTransferBaselineSnapshotData)
        trackerTransferBaselineSnapshotCache = baselineSnapshot
        let trackerAliasMapSnapshot: [String: String] = UserDefaults.standard.bool(forKey: "isProUser")
            ? TrackerAliasManager.shared.aliasMap
            : [:]

        let result = await Task.detached(priority: .utility) {
            DashboardViewModel.computeTrackerBreakdown(
                tasks: tasks,
                baselineSnapshot: baselineSnapshot,
                trackerAliasMap: trackerAliasMapSnapshot
            )
        }.value

        recentUploadData = result.uploadData
        recentDownloadData = result.downloadData
        trackerTransferBaselineSnapshotCache = result.baselineSnapshot
        if trackerTransferBaselineSnapshotData != result.encodedBaselineSnapshotData {
            trackerTransferBaselineSnapshotData = result.encodedBaselineSnapshotData
        }
    }

    private func normalizeBaselineTimestampIfNeeded() {
        guard baselineTimestamp > 0 else {
            baselineTimestamp = Date().timeIntervalSince1970
            return
        }
    }

    private func hydrateModuleOrderFromStorage() {
        let persistedIDs = (try? JSONDecoder().decode([String].self, from: moduleOrderStorageData)) ?? []
        let persisted = persistedIDs.compactMap(DashboardModuleType.init(rawValue:))

        let normalized = normalizeModuleOrder(persisted, availableModules: DashboardModuleType.defaultOrder)
        moduleOrder = normalized
        persistModuleOrderIfNeeded(normalized)
    }

    private func normalizeModuleOrder(
        _ currentOrder: [DashboardModuleType],
        availableModules: [DashboardModuleType]
    ) -> [DashboardModuleType] {
        let availableSet = Set(availableModules)
        let defaultAvailable = DashboardModuleType.defaultOrder.filter { availableSet.contains($0) }
        var deduped: [DashboardModuleType] = []
        var seen = Set<DashboardModuleType>()

        for module in currentOrder where availableSet.contains(module) {
            if seen.insert(module).inserted {
                deduped.append(module)
            }
        }

        for module in defaultAvailable where !seen.contains(module) {
            let followingModules = defaultAvailable.drop { $0 != module }.dropFirst()
            if let anchor = followingModules.first(where: { deduped.contains($0) }),
               let anchorIndex = deduped.firstIndex(of: anchor) {
                deduped.insert(module, at: anchorIndex)
            } else {
                deduped.append(module)
            }
            seen.insert(module)
        }

        return deduped
    }

    private func persistModuleOrderIfNeeded(_ modules: [DashboardModuleType]) {
        let ids = modules.map(\.rawValue)
        guard let serialized = try? JSONEncoder().encode(ids) else { return }
        guard moduleOrderStorageData != serialized else { return }
        moduleOrderStorageData = serialized
    }

    private static func buildServerRuntimeInputs(from servers: [ServerConfig]) -> [DashboardServerRuntimeInput] {
        var inputs: [DashboardServerRuntimeInput] = []
        inputs.reserveCapacity(max(servers.count, 1))

        for server in servers {
            inputs.append(
                DashboardServerRuntimeInput(
                    id: server.id,
                    name: server.name,
                    connectionState: server.connectionState,
                    isOnline: server.isOnline,
                    totalSeedingCount: server.totalSeedingCount,
                    totalDownloadingCount: server.totalDownloadingCount
                )
            )
        }

        return inputs
    }
}

private extension DashboardViewModel {
    nonisolated static let baselineDownloadKey = "dashboard.transferBaseline.download"
    nonisolated static let baselineUploadKey = "dashboard.transferBaseline.upload"
    nonisolated static let baselineTimestampKey = "dashboard.transferBaseline.timestamp"
    nonisolated static let trackerPalette: [Color] = [
        Color(red: 0.90, green: 0.24, blue: 0.22),
        Color(red: 0.19, green: 0.39, blue: 0.76),
        Color(red: 0.96, green: 0.52, blue: 0.14),
        Color(red: 0.20, green: 0.63, blue: 0.17),
        Color(red: 0.56, green: 0.27, blue: 0.68),
        Color(red: 0.81, green: 0.17, blue: 0.46),
        Color(red: 0.47, green: 0.15, blue: 0.13),
        Color(red: 0.36, green: 0.30, blue: 0.85),
        Color(red: 0.55, green: 0.37, blue: 0.12),
        Color(red: 0.12, green: 0.57, blue: 0.55),
        Color(red: 0.65, green: 0.37, blue: 0.15),
        Color(red: 0.30, green: 0.47, blue: 0.17)
    ]

    enum TrackerTransferDirection {
        case upload
        case download
    }

    nonisolated static func computeMergedGlobalSnapshot(
        apiSnapshot: GlobalStatsSnapshot,
        servers: [DashboardServerRuntimeInput],
        tasks: [TorrentTask],
        lastKnownStorageByServer: [UUID: DashboardServerStorageEntry]
    ) -> DashboardGlobalStatsMergeResult {
        var onlineServerIDs = Set<UUID>()
        onlineServerIDs.reserveCapacity(max(servers.count, 1))

        var totalSeedingCount = 0
        var totalDownloadingCount = 0

        for server in servers {
            let isOnline: Bool
            if server.connectionState == .online {
                isOnline = true
            } else if server.connectionState == .offline {
                isOnline = server.totalSeedingCount > 0 || server.totalDownloadingCount > 0
            } else {
                isOnline = true
            }

            if isOnline {
                onlineServerIDs.insert(server.id)
                totalSeedingCount += server.totalSeedingCount
                totalDownloadingCount += server.totalDownloadingCount
            }
        }

        var totalBandwidth: Int64 = 0
        if !onlineServerIDs.isEmpty {
            for task in tasks where onlineServerIDs.contains(task.serverID) {
                totalBandwidth += task.downloadSpeed + task.uploadSpeed
            }
        }
        if totalBandwidth <= 0 {
            totalBandwidth = apiSnapshot.totalBandwidth
        }

        var storageByServer: [UUID: DashboardServerStorageEntry] = [:]
        storageByServer.reserveCapacity(
            max(apiSnapshot.serverStorage.count + lastKnownStorageByServer.count, 1)
        )

        for entry in apiSnapshot.serverStorage {
            storageByServer[entry.id] = entry
        }
        for (serverID, cachedEntry) in lastKnownStorageByServer {
            if let existing = storageByServer[serverID], existing.remainingSpace != nil {
                continue
            }
            storageByServer[serverID] = cachedEntry
        }

        var mergedStorage: [DashboardServerStorageEntry] = []
        mergedStorage.reserveCapacity(max(servers.count, 1))

        var updatedStorageByServer = lastKnownStorageByServer
        var totalRemainingSpace: Int64 = 0

        for server in servers {
            let serverID = server.id
            let apiEntry = storageByServer[serverID]
            let connectionState = apiEntry?.connectionState ?? server.connectionState
            let isOnline = onlineServerIDs.contains(serverID)

            let mergedEntry = DashboardServerStorageEntry(
                id: serverID,
                serverName: server.name,
                defaultSavePath: apiEntry?.defaultSavePath ?? "--",
                remainingSpace: apiEntry?.remainingSpace,
                connectionState: connectionState,
                statusMessage: connectionState.statusMessage
            )
            mergedStorage.append(mergedEntry)

            if let remainingSpace = mergedEntry.remainingSpace, isOnline {
                totalRemainingSpace += remainingSpace
            }
            if mergedEntry.remainingSpace != nil {
                updatedStorageByServer[serverID] = mergedEntry
            }
        }

        let onlineServerCount = onlineServerIDs.count
        let failedServerCount = mergedStorage.filter { $0.connectionState == .offline }.count

        let mergedSnapshot = GlobalStatsSnapshot(
            totalSeedingCount: totalSeedingCount,
            totalDownloadingCount: totalDownloadingCount,
            totalBandwidth: totalBandwidth,
            totalRemainingSpace: totalRemainingSpace,
            totalAllTimeDownloaded: apiSnapshot.totalAllTimeDownloaded,
            totalAllTimeUploaded: apiSnapshot.totalAllTimeUploaded,
            onlineServerCount: onlineServerCount,
            failedServerCount: failedServerCount,
            hasConnectionIssue: onlineServerCount == 0 && failedServerCount > 0,
            hasReliableTransferTotals: apiSnapshot.hasReliableTransferTotals,
            serverStorage: mergedStorage,
            lastUpdatedAt: Date()
        )

        return DashboardGlobalStatsMergeResult(
            snapshot: mergedSnapshot,
            updatedStorageByServer: updatedStorageByServer
        )
    }

    nonisolated static let baselineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    nonisolated static func computeTrackerBreakdown(
        tasks: [TorrentTask],
        baselineSnapshot: TrackerTransferBaselineSnapshot?,
        trackerAliasMap: [String: String]
    ) -> TrackerTransferBreakdownResult {
        var baselineTasks = baselineSnapshot?.tasks ?? [:]
        var archivedByTracker = baselineSnapshot?.archivedByTracker ?? [:]
        baselineTasks.reserveCapacity(max(baselineTasks.count, tasks.count))
        archivedByTracker.reserveCapacity(max(archivedByTracker.count, 4))

        var grouped: [String: (uploaded: Int64, downloaded: Int64)] = [:]
        grouped.reserveCapacity(max(tasks.count / 2 + archivedByTracker.count, 4))

        for (trackerName, archived) in archivedByTracker {
            let uploaded = max(archived.uploaded, 0)
            let downloaded = max(archived.downloaded, 0)
            guard uploaded > 0 || downloaded > 0 else { continue }
            grouped[trackerName] = (uploaded, downloaded)
        }

        var activeTaskIDs = Set<String>()
        activeTaskIDs.reserveCapacity(max(tasks.count, 8))
        var activeServerIDs = Set<String>()
        activeServerIDs.reserveCapacity(max(tasks.count / 4, 4))

        for task in tasks {
            let serverIDString = task.serverID.uuidString
            let taskID = "\(serverIDString)_\(task.hash)"
            activeTaskIDs.insert(taskID)
            activeServerIDs.insert(serverIDString)
            let trackerName = TrackerNameManager.displayName(for: task.tracker, aliasMap: trackerAliasMap)
            let currentUploaded = max(task.uploaded, 0)
            let currentDownloaded = max(task.downloaded, 0)

            let baselineEntry = baselineTasks[taskID]
            let baselineUploaded: Int64
            let baselineDownloaded: Int64

            if let baselineEntry,
               baselineEntry.uploaded <= currentUploaded,
               baselineEntry.downloaded <= currentDownloaded {
                baselineUploaded = baselineEntry.uploaded
                baselineDownloaded = baselineEntry.downloaded
            } else {
                baselineUploaded = currentUploaded
                baselineDownloaded = currentDownloaded
            }

            baselineTasks[taskID] = TrackerTransferBaselineEntry(
                uploaded: baselineUploaded,
                downloaded: baselineDownloaded,
                latestUploaded: currentUploaded,
                latestDownloaded: currentDownloaded,
                trackerName: trackerName
            )

            let uploadDelta = max(currentUploaded - baselineUploaded, 0)
            let downloadDelta = max(currentDownloaded - baselineDownloaded, 0)
            guard uploadDelta > 0 || downloadDelta > 0 else { continue }
            guard trackerName != "--" else { continue }

            var bucket = grouped[trackerName] ?? (0, 0)
            bucket.uploaded += uploadDelta
            bucket.downloaded += downloadDelta
            grouped[trackerName] = bucket
        }

        if baselineTasks.count > activeTaskIDs.count {
            var filteredBaselineTasks: [String: TrackerTransferBaselineEntry] = [:]
            filteredBaselineTasks.reserveCapacity(baselineTasks.count)

            for (taskID, entry) in baselineTasks {
                if activeTaskIDs.contains(taskID) {
                    filteredBaselineTasks[taskID] = entry
                    continue
                }
                guard let separatorIndex = taskID.firstIndex(of: "_") else {
                    filteredBaselineTasks[taskID] = entry
                    continue
                }
                let serverID = String(taskID[..<separatorIndex])
                guard activeServerIDs.contains(serverID) else {
                    filteredBaselineTasks[taskID] = entry
                    continue
                }

                let latestUploaded = max(entry.latestUploaded ?? entry.uploaded, entry.uploaded)
                let latestDownloaded = max(entry.latestDownloaded ?? entry.downloaded, entry.downloaded)
                let uploadDelta = max(latestUploaded - entry.uploaded, 0)
                let downloadDelta = max(latestDownloaded - entry.downloaded, 0)
                let trackerName = (entry.trackerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                guard trackerName != "--",
                      !trackerName.isEmpty,
                      (uploadDelta > 0 || downloadDelta > 0) else {
                    continue
                }

                var archived = archivedByTracker[trackerName]
                    ?? TrackerTransferBaselineEntry(
                        uploaded: 0,
                        downloaded: 0,
                        latestUploaded: nil,
                        latestDownloaded: nil,
                        trackerName: nil
                    )
                archived = TrackerTransferBaselineEntry(
                    uploaded: max(archived.uploaded + uploadDelta, 0),
                    downloaded: max(archived.downloaded + downloadDelta, 0),
                    latestUploaded: nil,
                    latestDownloaded: nil,
                    trackerName: nil
                )
                archivedByTracker[trackerName] = archived

                var bucket = grouped[trackerName] ?? (0, 0)
                bucket.uploaded += uploadDelta
                bucket.downloaded += downloadDelta
                grouped[trackerName] = bucket
            }

            baselineTasks = filteredBaselineTasks
        }

        if !activeTaskIDs.isEmpty &&
            baselineTasks.count > activeTaskIDs.count + max(1024, activeTaskIDs.count / 10) {
            baselineTasks = baselineTasks.filter { taskID, _ in
                if activeTaskIDs.contains(taskID) { return true }
                guard let separatorIndex = taskID.firstIndex(of: "_") else { return true }
                let serverID = String(taskID[..<separatorIndex])
                return !activeServerIDs.contains(serverID)
            }
        }

        var aggregates: [TrackerTransferAggregate] = []
        aggregates.reserveCapacity(grouped.count)
        for (key, value) in grouped {
            aggregates.append(
                TrackerTransferAggregate(
                    trackerName: key,
                    uploadedBytes: max(value.uploaded, 0),
                    downloadedBytes: max(value.downloaded, 0)
                )
            )
        }

        let snapshot = TrackerTransferBaselineSnapshot(
            tasks: baselineTasks,
            archivedByTracker: archivedByTracker
        )

        return TrackerTransferBreakdownResult(
            uploadData: buildTransferData(
                aggregates: aggregates,
                direction: .upload
            ),
            downloadData: buildTransferData(
                aggregates: aggregates,
                direction: .download
            ),
            baselineSnapshot: snapshot,
            encodedBaselineSnapshotData: encodeTrackerBaselineSnapshot(snapshot)
        )
    }

    nonisolated static func buildTransferData(
        aggregates: [TrackerTransferAggregate],
        direction: TrackerTransferDirection
    ) -> [TrackerTransferData] {
        var items: [(trackerName: String, bytes: Int64)] = []
        items.reserveCapacity(aggregates.count)

        for aggregate in aggregates {
            let bytes: Int64
            switch direction {
            case .upload:
                bytes = aggregate.uploadedBytes
            case .download:
                bytes = aggregate.downloadedBytes
            }

            if bytes > 0 {
                items.append((trackerName: aggregate.trackerName, bytes: bytes))
            }
        }

        items.sort { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.trackerName.localizedCaseInsensitiveCompare(rhs.trackerName) == .orderedAscending
        }

        let colorByTracker = trackerColorMap(for: items.map(\.trackerName))
        var output: [TrackerTransferData] = []
        output.reserveCapacity(items.count)

        for item in items {
            output.append(
                TrackerTransferData(
                    id: item.trackerName,
                    trackerName: item.trackerName,
                    bytes: item.bytes,
                    color: colorByTracker[item.trackerName] ?? trackerColor(for: item.trackerName)
                )
            )
        }

        return output
    }

    nonisolated static func trackerColor(for trackerName: String) -> Color {
        let palette = trackerPalette
        guard !palette.isEmpty else { return .blue }
        let index = Int(stableTrackerHash(trackerName) % UInt64(palette.count))
        return palette[index]
    }

    nonisolated private static func trackerColorMap(
        for trackerNames: [String]
    ) -> [String: Color] {
        let palette = trackerPalette
        guard !palette.isEmpty else { return [:] }

        let uniqueNames = Array(Set(trackerNames))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var assigned: [String: Color] = [:]
        assigned.reserveCapacity(uniqueNames.count)

        var used = Set<Int>()
        used.reserveCapacity(min(uniqueNames.count, palette.count))
        let collisionStep = 7

        for name in uniqueNames {
            let baseIndex = Int(stableTrackerHash(name) % UInt64(palette.count))
            var selectedIndex = baseIndex

            if used.contains(baseIndex) {
                for attempt in 1..<palette.count {
                    let candidate = (baseIndex + attempt * collisionStep) % palette.count
                    if !used.contains(candidate) {
                        selectedIndex = candidate
                        break
                    }
                }
            }

            if used.count < palette.count {
                used.insert(selectedIndex)
                assigned[name] = palette[selectedIndex]
            } else {
                let mixed = stableTrackerHash(name) &* 137 &+ 17
                let hue = Double(mixed % 360) / 360.0
                assigned[name] = Color(hue: hue, saturation: 0.78, brightness: 0.86)
            }
        }

        return assigned
    }

    nonisolated private static func stableTrackerHash(_ trackerName: String) -> UInt64 {
        var hash: UInt64 = 5381
        for scalar in trackerName.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return hash
    }

    nonisolated static func decodeTrackerBaselineSnapshot(from data: Data) -> TrackerTransferBaselineSnapshot? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TrackerTransferBaselineSnapshot.self, from: data)
    }

    nonisolated static func encodeTrackerBaselineSnapshot(_ snapshot: TrackerTransferBaselineSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }
}
