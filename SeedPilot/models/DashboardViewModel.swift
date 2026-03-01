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

    init(id: String? = nil, trackerName: String, bytes: Int64, color: Color) {
        self.id = id ?? trackerName
        self.trackerName = trackerName
        self.bytes = bytes
        self.color = color
    }
}

private struct TrackerTransferAggregate: Sendable {
    let trackerName: String
    let uploadedBytes: Int64
    let downloadedBytes: Int64
}

private struct TrackerTransferBaselineEntry: Codable, Sendable, Equatable {
    let uploaded: Int64
    let downloaded: Int64
}

private struct TrackerTransferBaselineSnapshot: Codable, Sendable {
    let dayStamp: String
    let tasks: [String: TrackerTransferBaselineEntry]
}

private struct TrackerTransferRollingSnapshot: Codable, Sendable {
    let timestamp: Date
    let tasks: [String: TrackerTransferBaselineEntry]
}

private struct TrackerTransferComputationResult: Sendable {
    let aggregates: [TrackerTransferAggregate]
    let baselineSnapshot: TrackerTransferBaselineSnapshot
    let rollingSnapshots: [TrackerTransferRollingSnapshot]
}

private struct DashboardServerRuntimeInput: Sendable {
    let id: UUID
    let name: String
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
    @Published private(set) var todayUploadData: [TrackerTransferData] = []
    @Published private(set) var todayDownloadData: [TrackerTransferData] = []

    @AppStorage(DashboardConfig.Keys.moduleOrder) private var moduleOrderStorageData: Data = Data()
    @AppStorage("dashboard.todayTransferBaselineSnapshot") private var trackerStatsBaselineSnapshotData: Data = Data()
    @AppStorage("dashboard.todayTransferRollingSnapshots") private var trackerStatsRollingSnapshotsData: Data = Data()

    private let statsManager: GlobalStatsManager
    private var autoRefreshTask: Task<Void, Never>?
    private var trackerStatsComputationTask: Task<Void, Never>?
    private var trackerStatsTasksProvider: (@MainActor () -> [TorrentTask])?
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

    func configureTrackerStatsTasksProvider(_ provider: @escaping @MainActor () -> [TorrentTask]) {
        trackerStatsTasksProvider = provider
    }

    func calculateTrackerStats() {
        guard let trackerStatsTasksProvider else { return }
        calculateTrackerStats(from: trackerStatsTasksProvider())
    }

    func calculateTrackerStats(from tasks: [TorrentTask]) {
        trackerStatsComputationTask?.cancel()

        let dayStamp = Self.trackerStatsDayStampFormatter.string(from: Date())
        let now = Date()
        let baselineSnapshot = Self.decodeTrackerBaselineSnapshot(from: trackerStatsBaselineSnapshotData)
        let rollingSnapshots = Self.decodeTrackerRollingSnapshots(from: trackerStatsRollingSnapshotsData)
        let trackerAliasMapSnapshot: [String: String] = UserDefaults.standard.bool(forKey: "isProUser")
            ? TrackerAliasManager.shared.aliasMap
            : [:]

        trackerStatsComputationTask = Task {
            [tasks, dayStamp, now, baselineSnapshot, rollingSnapshots, trackerAliasMapSnapshot] in
            let result = await Task.detached(priority: .utility) {
                DashboardViewModel.computeTrackerStats(
                    tasks: tasks,
                    dayStamp: dayStamp,
                    now: now,
                    baselineSnapshot: baselineSnapshot,
                    rollingSnapshots: rollingSnapshots,
                    trackerAliasMap: trackerAliasMapSnapshot
                )
            }.value

            guard !Task.isCancelled else { return }

            todayUploadData = Self.buildTransferData(aggregates: result.aggregates, direction: .upload)
            todayDownloadData = Self.buildTransferData(aggregates: result.aggregates, direction: .download)
            trackerStatsBaselineSnapshotData = Self.encodeTrackerBaselineSnapshot(result.baselineSnapshot)
            trackerStatsRollingSnapshotsData = Self.encodeTrackerRollingSnapshots(result.rollingSnapshots)
        }
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
            hasLoadedInitialSnapshot = true
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

        let serverInputs = Self.buildServerRuntimeInputs(from: servers)
        var cachedStorageByServer = lastKnownStorageByServer

        isRefreshing = true
        await statsManager.refresh(servers: servers, force: force)
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

        // Retry both full outage and partial server failures.
        let shouldRetry = latestResult.snapshot.hasConnectionIssue || latestResult.snapshot.failedServerCount > 0

        var resolvedSnapshot = latestResult.snapshot
        if shouldRetry, let retried = await retryGlobalStats(servers: servers, retryCount: 2) {
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
                globalSnapshot = cachedResult.snapshot
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

        lastKnownStorageByServer = cachedStorageByServer
        isRefreshing = false
        hasLoadedInitialSnapshot = true
    }

    func prefetchForLaunch(servers: [ServerConfig], tasks: [TorrentTask]) async {
        await refreshGlobalStats(servers: servers, tasks: tasks, force: true)
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

    private static func buildServerRuntimeInputs(from servers: [ServerConfig]) -> [DashboardServerRuntimeInput] {
        var inputs: [DashboardServerRuntimeInput] = []
        inputs.reserveCapacity(max(servers.count, 1))

        for server in servers {
            inputs.append(
                DashboardServerRuntimeInput(
                    id: server.id,
                    name: server.name,
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
    enum TrackerTransferDirection {
        case upload
        case download
    }

    static let trackerPalette: [Color] = [
        .orange, .green, .blue, .pink, .indigo,
        .mint, .teal, .red, .cyan, .brown
    ]

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
            if server.isOnline == true {
                isOnline = true
            } else if server.isOnline == false {
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
            for task in tasks {
                if onlineServerIDs.contains(task.serverID) {
                    totalBandwidth += task.downloadSpeed + task.uploadSpeed
                }
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
                updatedStorageByServer[serverID] = mergedEntry
            }
        }

        let onlineServerCount = onlineServerIDs.count
        let failedServerCount = max(servers.count - onlineServerCount, 0)

        let mergedSnapshot = GlobalStatsSnapshot(
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

        return DashboardGlobalStatsMergeResult(
            snapshot: mergedSnapshot,
            updatedStorageByServer: updatedStorageByServer
        )
    }

    nonisolated static func computeTrackerStats(
        tasks: [TorrentTask],
        dayStamp: String,
        now: Date,
        baselineSnapshot: TrackerTransferBaselineSnapshot?,
        rollingSnapshots: [TrackerTransferRollingSnapshot],
        trackerAliasMap: [String: String]
    ) -> TrackerTransferComputationResult {
        var currentTaskCounters: [String: TrackerTransferBaselineEntry] = [:]
        currentTaskCounters.reserveCapacity(max(tasks.count, 8))
        for task in tasks {
            let taskID = "\(task.serverID.uuidString)_\(task.hash)"
            let uploaded = max(task.uploaded, 0)
            let downloaded = max(task.downloaded, 0)
            // Keep zero counters in rolling snapshots so midnight interpolation can preserve
            // "0 -> positive" transfers that start after midnight.
            currentTaskCounters[taskID] = TrackerTransferBaselineEntry(uploaded: uploaded, downloaded: downloaded)
        }

        let updatedRollingSnapshots = normalizedRollingSnapshots(
            rollingSnapshots,
            appending: TrackerTransferRollingSnapshot(timestamp: now, tasks: currentTaskCounters),
            now: now
        )

        var baselineTasks = resolveBaselineTasks(
            dayStamp: dayStamp,
            now: now,
            currentTaskCounters: currentTaskCounters,
            baselineSnapshot: baselineSnapshot,
            rollingSnapshots: updatedRollingSnapshots
        )

        var grouped: [String: (uploaded: Int64, downloaded: Int64)] = [:]
        grouped.reserveCapacity(max(tasks.count / 2, 4))

        for task in tasks {
            let taskID = "\(task.serverID.uuidString)_\(task.hash)"
            let currentUploaded = max(task.uploaded, 0)
            let currentDownloaded = max(task.downloaded, 0)

            let baselineEntry = baselineTasks[taskID]
            let effectiveBaseline: TrackerTransferBaselineEntry

            if let baselineEntry,
               baselineEntry.uploaded <= currentUploaded,
               baselineEntry.downloaded <= currentDownloaded {
                effectiveBaseline = baselineEntry
            } else {
                // Counter reset / task re-added / first time seen today: treat current counters as baseline.
                let resetBaseline = TrackerTransferBaselineEntry(
                    uploaded: currentUploaded,
                    downloaded: currentDownloaded
                )
                baselineTasks[taskID] = resetBaseline
                effectiveBaseline = resetBaseline
            }

            if baselineEntry == nil {
                baselineTasks[taskID] = effectiveBaseline
            }

            let uploadDelta = max(currentUploaded - effectiveBaseline.uploaded, 0)
            let downloadDelta = max(currentDownloaded - effectiveBaseline.downloaded, 0)
            guard uploadDelta > 0 || downloadDelta > 0 else { continue }

            let trackerName = TrackerNameManager.displayName(for: task.tracker, aliasMap: trackerAliasMap)
            guard trackerName != "--" else { continue }

            var bucket = grouped[trackerName] ?? (0, 0)
            bucket.uploaded += uploadDelta
            bucket.downloaded += downloadDelta
            grouped[trackerName] = bucket
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

        let snapshot = TrackerTransferBaselineSnapshot(dayStamp: dayStamp, tasks: baselineTasks)
        return TrackerTransferComputationResult(
            aggregates: aggregates,
            baselineSnapshot: snapshot,
            rollingSnapshots: updatedRollingSnapshots
        )
    }

    static func buildTransferData(
        aggregates: [TrackerTransferAggregate],
        direction: TrackerTransferDirection
    ) -> [TrackerTransferData] {
        var output: [TrackerTransferData] = []
        output.reserveCapacity(aggregates.count)

        for aggregate in aggregates {
            let bytes: Int64
            switch direction {
            case .upload:
                bytes = aggregate.uploadedBytes
            case .download:
                bytes = aggregate.downloadedBytes
            }

            if bytes > 0 {
                output.append(
                    TrackerTransferData(
                        trackerName: aggregate.trackerName,
                        bytes: bytes,
                        color: trackerColor(for: aggregate.trackerName)
                    )
                )
            }
        }

        output.sort { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.trackerName.localizedCaseInsensitiveCompare(rhs.trackerName) == .orderedAscending
        }

        return output
    }

    static func trackerColor(for trackerName: String) -> Color {
        let palette = trackerPalette
        guard !palette.isEmpty else { return .blue }

        var hash = 5381
        for scalar in trackerName.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }

        return palette[abs(hash) % palette.count]
    }

    static func decodeTrackerBaselineSnapshot(from data: Data) -> TrackerTransferBaselineSnapshot? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TrackerTransferBaselineSnapshot.self, from: data)
    }

    static func encodeTrackerBaselineSnapshot(_ snapshot: TrackerTransferBaselineSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    static func decodeTrackerRollingSnapshots(from data: Data) -> [TrackerTransferRollingSnapshot] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([TrackerTransferRollingSnapshot].self, from: data)) ?? []
    }

    static func encodeTrackerRollingSnapshots(_ snapshots: [TrackerTransferRollingSnapshot]) -> Data {
        (try? JSONEncoder().encode(snapshots)) ?? Data()
    }

    nonisolated static func normalizedRollingSnapshots(
        _ snapshots: [TrackerTransferRollingSnapshot],
        appending current: TrackerTransferRollingSnapshot,
        now: Date
    ) -> [TrackerTransferRollingSnapshot] {
        var sorted = snapshots.sorted { $0.timestamp < $1.timestamp }

        if let last = sorted.last,
           abs(last.timestamp.timeIntervalSince(current.timestamp)) < 30,
           last.tasks == current.tasks {
            // Avoid duplicate writes from closely spaced onAppear/scenePhase triggers.
        } else {
            sorted.append(current)
        }

        let prunedByAge = sorted.filter {
            now.timeIntervalSince($0.timestamp) <= Self.maxRollingSnapshotAge
        }

        if prunedByAge.count <= Self.maxRollingSnapshotCount {
            return prunedByAge
        }

        return Array(prunedByAge.suffix(Self.maxRollingSnapshotCount))
    }

    nonisolated static func resolveBaselineTasks(
        dayStamp: String,
        now: Date,
        currentTaskCounters: [String: TrackerTransferBaselineEntry],
        baselineSnapshot: TrackerTransferBaselineSnapshot?,
        rollingSnapshots: [TrackerTransferRollingSnapshot]
    ) -> [String: TrackerTransferBaselineEntry] {
        if let baselineSnapshot, baselineSnapshot.dayStamp == dayStamp {
            return baselineSnapshot.tasks
        }

        guard !currentTaskCounters.isEmpty else { return [:] }

        let midnight = trackerStatsCalendar.startOfDay(for: now)
        let beforeMidnight = rollingSnapshots.last(where: { $0.timestamp <= midnight })
        let afterMidnight = rollingSnapshots.first(where: { $0.timestamp >= midnight })

        var derived: [String: TrackerTransferBaselineEntry] = [:]
        derived.reserveCapacity(currentTaskCounters.count)

        for (taskID, current) in currentTaskCounters {
            let beforeEntry = beforeMidnight?.tasks[taskID]
            let afterEntry = afterMidnight?.tasks[taskID]

            let estimated = estimateMidnightBaseline(
                current: current,
                midnight: midnight,
                beforeTimestamp: beforeMidnight?.timestamp,
                beforeEntry: beforeEntry,
                afterTimestamp: afterMidnight?.timestamp,
                afterEntry: afterEntry
            ) ?? current

            derived[taskID] = clampBaselineEntry(estimated, toCurrent: current)
        }

        return derived
    }

    nonisolated static func estimateMidnightBaseline(
        current: TrackerTransferBaselineEntry,
        midnight: Date,
        beforeTimestamp: Date?,
        beforeEntry: TrackerTransferBaselineEntry?,
        afterTimestamp: Date?,
        afterEntry: TrackerTransferBaselineEntry?
    ) -> TrackerTransferBaselineEntry? {
        switch (beforeTimestamp, beforeEntry, afterTimestamp, afterEntry) {
        case let (.some(beforeTime), .some(before), .some(afterTime), .some(after)):
            let beforeClamped = clampBaselineEntry(before, toCurrent: current)
            let afterClamped = clampBaselineEntry(after, toCurrent: current)

            guard afterTime > beforeTime else {
                return afterTime >= midnight ? afterClamped : beforeClamped
            }

            // Counters can reset after client restart / task re-add; interpolation is invalid in that case.
            guard after.uploaded >= before.uploaded, after.downloaded >= before.downloaded else {
                return afterTime >= midnight ? afterClamped : beforeClamped
            }

            let total = afterTime.timeIntervalSince(beforeTime)
            let elapsed = midnight.timeIntervalSince(beforeTime)
            guard total > 0 else { return afterClamped }

            let progress = min(max(elapsed / total, 0), 1)
            return clampBaselineEntry(
                TrackerTransferBaselineEntry(
                    uploaded: interpolatedInt64(before.uploaded, after.uploaded, progress: progress),
                    downloaded: interpolatedInt64(before.downloaded, after.downloaded, progress: progress)
                ),
                toCurrent: current
            )

        case let (_, _, .some(_), .some(after)):
            return clampBaselineEntry(after, toCurrent: current)

        case let (.some(_), .some(before), _, _):
            return clampBaselineEntry(before, toCurrent: current)

        default:
            return nil
        }
    }

    nonisolated static func clampBaselineEntry(
        _ baseline: TrackerTransferBaselineEntry,
        toCurrent current: TrackerTransferBaselineEntry
    ) -> TrackerTransferBaselineEntry {
        TrackerTransferBaselineEntry(
            uploaded: min(max(baseline.uploaded, 0), current.uploaded),
            downloaded: min(max(baseline.downloaded, 0), current.downloaded)
        )
    }

    nonisolated static func interpolatedInt64(_ start: Int64, _ end: Int64, progress: Double) -> Int64 {
        let value = Double(start) + (Double(end - start) * progress)
        return Int64(value.rounded())
    }

    static let trackerStatsDayStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated static let trackerStatsCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    nonisolated static let maxRollingSnapshotCount = 48
    nonisolated static let maxRollingSnapshotAge: TimeInterval = 72 * 60 * 60
}
