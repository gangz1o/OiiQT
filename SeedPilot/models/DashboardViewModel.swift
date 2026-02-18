//
//  DashboardViewModel.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var globalSnapshot = GlobalStatsSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUsingCachedFallback = false
    @Published private(set) var moduleOrder: [DashboardModuleType] = DashboardModuleType.defaultOrder

    @AppStorage(DashboardConfig.Keys.moduleOrder) private var moduleOrderStorageData: Data = Data()

    private let statsManager: GlobalStatsManager
    private var autoRefreshTask: Task<Void, Never>?
    private var lastSuccessfulSnapshot: GlobalStatsSnapshot?
    private var lastKnownStorageByServer: [UUID: DashboardServerStorageEntry] = [:]

    init(statsManager: GlobalStatsManager) {
        self.statsManager = statsManager
        hydrateModuleOrderFromStorage()
    }

    init() {
        self.statsManager = .shared
        hydrateModuleOrderFromStorage()
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
                await self.refreshGlobalStats(servers: currentServers, tasks: currentTasks)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshGlobalStats(servers: [ServerConfig], tasks: [TorrentTask], force: Bool = false) async {
        guard !servers.isEmpty else {
            isRefreshing = false
            isUsingCachedFallback = false
            globalSnapshot = GlobalStatsSnapshot(
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
            lastSuccessfulSnapshot = nil
            return
        }

        isRefreshing = true
        await statsManager.refresh(servers: servers, force: force)
        let latestSnapshot = mergeSnapshot(statsManager.snapshot, with: servers, tasks: tasks)

        // Retry both full outage and partial server failures.
        let shouldRetry = latestSnapshot.hasConnectionIssue || latestSnapshot.failedServerCount > 0

        var resolvedSnapshot = latestSnapshot
        if shouldRetry, let retried = await retryGlobalStats(servers: servers, retryCount: 2) {
            let mergedRetried = mergeSnapshot(retried, with: servers, tasks: tasks)
            resolvedSnapshot = betterSnapshot(lhs: resolvedSnapshot, rhs: mergedRetried)
        }

        if resolvedSnapshot.hasConnectionIssue {
            if let cached = lastSuccessfulSnapshot {
                globalSnapshot = mergeSnapshot(cached, with: servers, tasks: tasks)
                isUsingCachedFallback = true
            } else {
                globalSnapshot = resolvedSnapshot
                isUsingCachedFallback = false
            }
        } else {
            globalSnapshot = resolvedSnapshot
            lastSuccessfulSnapshot = resolvedSnapshot
            isUsingCachedFallback = false
        }

        isRefreshing = false
    }

    private func retryGlobalStats(servers: [ServerConfig], retryCount: Int) async -> GlobalStatsSnapshot? {
        var bestSnapshot: GlobalStatsSnapshot?

        for _ in 0..<retryCount {
            guard !Task.isCancelled else { return nil }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return nil }

            await statsManager.refresh(servers: servers, force: true)
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

    private func mergeSnapshot(_ apiSnapshot: GlobalStatsSnapshot, with servers: [ServerConfig], tasks: [TorrentTask]) -> GlobalStatsSnapshot {
        let onlineServers = servers.filter { server in
            if server.isOnline == true { return true }
            if server.isOnline == false {
                // Keep server in aggregation when runtime stats still indicate activity.
                return server.totalSeedingCount > 0 || server.totalDownloadingCount > 0
            }
            return true
        }
        let onlineServerIDs = Set(onlineServers.map(\.id))

        var totalSeedingCount = 0
        var totalDownloadingCount = 0
        for server in onlineServers {
            totalSeedingCount += server.totalSeedingCount
            totalDownloadingCount += server.totalDownloadingCount
        }

        let tasksByServer = Dictionary(grouping: tasks, by: \.serverID)
        var totalBandwidth: Int64 = 0
        for serverID in onlineServerIDs {
            guard let serverTasks = tasksByServer[serverID] else { continue }
            totalBandwidth += serverTasks.reduce(Int64(0)) { $0 + $1.downloadSpeed + $1.uploadSpeed }
        }
        if totalBandwidth <= 0 {
            totalBandwidth = apiSnapshot.totalBandwidth
        }

        var storageByServer = Dictionary(uniqueKeysWithValues: apiSnapshot.serverStorage.map { ($0.id, $0) })
        for (serverID, cachedEntry) in lastKnownStorageByServer {
            guard storageByServer[serverID] == nil || storageByServer[serverID]?.remainingSpace == nil else { continue }
            storageByServer[serverID] = cachedEntry
        }

        var mergedStorage: [DashboardServerStorageEntry] = []
        mergedStorage.reserveCapacity(servers.count)

        var totalRemainingSpace: Int64 = 0
        for server in servers {
            let serverID = server.id
            let isOnline = onlineServerIDs.contains(serverID)
            let apiEntry = storageByServer[serverID]

            let mergedEntry = DashboardServerStorageEntry(
                id: serverID,
                serverName: server.name,
                defaultSavePath: apiEntry?.defaultSavePath ?? "--",
                remainingSpace: apiEntry?.remainingSpace,
                isOnline: isOnline,
                statusMessage: isOnline ? "在线" : "连接异常"
            )
            mergedStorage.append(mergedEntry)

            if let remainingSpace = mergedEntry.remainingSpace, isOnline {
                totalRemainingSpace += remainingSpace
            }
            if mergedEntry.remainingSpace != nil {
                lastKnownStorageByServer[serverID] = mergedEntry
            }
        }

        let onlineServerCount = onlineServers.count
        let failedServerCount = max(servers.count - onlineServerCount, 0)

        return GlobalStatsSnapshot(
            totalSeedingCount: totalSeedingCount,
            totalDownloadingCount: totalDownloadingCount,
            totalBandwidth: totalBandwidth,
            totalRemainingSpace: totalRemainingSpace,
            onlineServerCount: onlineServerCount,
            failedServerCount: failedServerCount,
            hasConnectionIssue: onlineServerCount == 0,
            serverStorage: mergedStorage,
            lastUpdatedAt: Date()
        )
    }

    private func betterSnapshot(lhs: GlobalStatsSnapshot, rhs: GlobalStatsSnapshot) -> GlobalStatsSnapshot {
        if rhs.onlineServerCount != lhs.onlineServerCount {
            return rhs.onlineServerCount > lhs.onlineServerCount ? rhs : lhs
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
}
