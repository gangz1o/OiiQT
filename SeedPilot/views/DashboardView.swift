//
//  DashboardView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var dashboardViewModel: DashboardViewModel
    @State private var hasSyncedModuleOrder = false

    init(viewModel: DashboardViewModel) {
        self.dashboardViewModel = viewModel
    }

    @AppStorage("refreshRate") private var refreshRate: Int = 5
    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false
    @AppStorage(DashboardConfig.Keys.showTodayTransfer) private var showTodayTransfer: Bool = false
    @AppStorage(DashboardConfig.Keys.showRecentFinished) private var showRecentFinished: Bool = false
    @AppStorage(DashboardConfig.Keys.showLiveTraffic) private var showLiveTraffic: Bool = true
    @AppStorage(DashboardConfig.Keys.showGlobalAssets) private var showGlobalAssets: Bool = true
    @AppStorage(DashboardConfig.Keys.showServerStatus) private var showServerStatus: Bool = true
    @AppStorage(DashboardConfig.Keys.showStorageAudit) private var showStorageAudit: Bool = false

    @State private var draggedModule: DashboardModuleType?
    @State private var highlightedDropTarget: DashboardModuleType?
    @State private var activeHoverTarget: DashboardModuleType?
    @State private var hasActivatedStorageAudit = false

    private var isProCinemaEnabled: Bool {
        proDashboardBackgroundEnabled || UserDefaults.standard.bool(forKey: "proDashboardBackgroundEnabled")
    }

    private var shouldStartGlobalStatsRefresh: Bool {
        showTodayTransfer || showGlobalAssets || (showStorageAudit && hasActivatedStorageAudit)
    }

    private var dashboardAutoRefreshInterval: TimeInterval? {
        guard refreshRate > 0 else { return nil }
        return TimeInterval(refreshRate)
    }

    private var shouldShowStatsSkeleton: Bool {
        shouldStartGlobalStatsRefresh &&
        !appStateManager.servers.isEmpty &&
        !dashboardViewModel.hasLoadedInitialSnapshot
    }

    private var shouldShowServerSkeleton: Bool {
        showServerStatus &&
        !appStateManager.servers.isEmpty &&
        !appStateManager.hasInitialDataLoaded
    }

    private var combinedTorrents: [TorrentTask] {
        appStateManager.allTasks
    }

    private var enabledModules: [DashboardModuleType] {
        var modules: [DashboardModuleType] = []
        if isProCinemaEnabled { modules.append(.proPosterWall) }
        if showLiveTraffic { modules.append(.liveTraffic) }
        if showTodayTransfer { modules.append(.todayTransfer) }
        if showGlobalAssets { modules.append(.globalAssets) }
        if showServerStatus { modules.append(.serverStatus) }
        if showStorageAudit { modules.append(.storageAudit) }
        if showRecentFinished { modules.append(.recentFinished) }
        return modules
    }

    private var allModulesDisabled: Bool {
        !isProCinemaEnabled &&
        !showLiveTraffic &&
        !showTodayTransfer &&
        !showGlobalAssets &&
        !showServerStatus &&
        !showStorageAudit &&
        !showRecentFinished
    }

    private var visibleModules: [DashboardModuleType] {
        let enabledSet = Set(enabledModules)
        return dashboardViewModel.moduleOrder.filter { module in
            enabledSet.contains(module) && isModuleRenderable(module)
        }
    }

    private var enabledModuleKey: String {
        enabledModules.map(\.rawValue).joined(separator: "|")
    }

    private var globalStatsRefreshKey: String {
        appStateManager.servers
            .map {
                "\($0.id.uuidString)|\($0.type.rawValue)|\($0.address)|\($0.port)|\($0.username)|\($0.useHTTPS)|\($0.rpcPath)|\($0.allowInsecureSSL)"
            }
            .sorted()
            .joined(separator: "||")
    }

    private var layoutAnimationKey: String {
        [
            isProCinemaEnabled ? "1" : "0",
            showLiveTraffic ? "1" : "0",
            showTodayTransfer ? "1" : "0",
            showGlobalAssets ? "1" : "0",
            showServerStatus ? "1" : "0",
            showStorageAudit ? "1" : "0",
            showRecentFinished ? "1" : "0",
            dashboardViewModel.moduleOrder.map(\.rawValue).joined(separator: ",")
        ].joined(separator: "|")
    }

    private var isDashboardTabActive: Bool {
        appStateManager.selectedTab == .dashboard
    }

    var body: some View {
        Group {
            if allModulesDisabled {
                DashboardModulesDisabledEmptyStateView {
                    appStateManager.selectedTab = .settings
                    appStateManager.settingsRoute = .dashboardCustomization
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(visibleModules) { module in
                            moduleContent(for: module)
                                .frame(minHeight: estimatedModuleMinHeight(for: module), alignment: .top)
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .opacity(draggedModule == module ? 0.6 : 1)
                                .scaleEffect(draggedModule == module ? 1.01 : 1)
                                // 性能优化：shadow 应用在纯背景形状上，避免对整个模块子视图树做 alpha 遮罩计算
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.clear)
                                        .shadow(
                                            color: .black.opacity(draggedModule == module ? 0.16 : 0.04),
                                            radius: draggedModule == module ? 14 : 8,
                                            x: 0,
                                            y: draggedModule == module ? 8 : 4
                                        )
                                )
                                .overlay {
                                    if highlightedDropTarget == module, draggedModule != module {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                Color.gray.opacity(0.45),
                                                style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                                            )
                                    }
                                }
                                .zIndex(draggedModule == module ? 1000 : 0)
                                .draggable(module.rawValue)
                                .onDrag {
                                    beginDragging(module)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    handleDrop(items: items, onto: module)
                                } isTargeted: { isTargeted in
                                    handleDropTargetChanged(isTargeted: isTargeted, target: module)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .animation(.spring(response: 0.34, dampingFraction: 0.88), value: layoutAnimationKey)
                }
                .defersAppRefreshWhileScrolling("dashboard.modules")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(globalStatsRefreshKey)|\(shouldStartGlobalStatsRefresh)|\(isDashboardTabActive)|\(refreshRate)") {
            guard isDashboardTabActive else {
                dashboardViewModel.stopAutoRefresh()
                return
            }

            if shouldStartGlobalStatsRefresh {
                dashboardViewModel.startAutoRefresh(
                    serversProvider: { appStateManager.servers },
                    tasksProvider: { appStateManager.allTasks },
                    interval: dashboardAutoRefreshInterval,
                    shouldPauseRefresh: { appStateManager.isRefreshSuspendedForScrolling },
                    remainingPauseCooldownNanoseconds: {
                        appStateManager.remainingRefreshSuspensionCooldownNanoseconds()
                    }
                )
            } else {
                dashboardViewModel.stopAutoRefresh()
            }
        }
        .onDisappear {
            dashboardViewModel.stopAutoRefresh()
        }
        .onAppear {
            guard isDashboardTabActive else { return }

            if !hasSyncedModuleOrder {
                dashboardViewModel.syncModuleOrder(availableModules: enabledModules)
                hasSyncedModuleOrder = true
            }
        }
        .onChange(of: enabledModuleKey) { _, _ in
            if !showStorageAudit {
                hasActivatedStorageAudit = false
            }
            dashboardViewModel.syncModuleOrder(availableModules: enabledModules)
        }
        .onChange(of: draggedModule) { _, newValue in
            guard newValue == nil else { return }
            highlightedDropTarget = nil
            activeHoverTarget = nil
        }
        .onChange(of: appStateManager.selectedTab) { _, newValue in
            guard newValue == .dashboard else {
                dashboardViewModel.stopAutoRefresh()
                return
            }

            if !hasSyncedModuleOrder {
                dashboardViewModel.syncModuleOrder(availableModules: enabledModules)
                hasSyncedModuleOrder = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                dashboardViewModel.stopAutoRefresh()
                return
            }

            guard appStateManager.selectedTab == .dashboard else { return }

            if shouldStartGlobalStatsRefresh {
                dashboardViewModel.startAutoRefresh(
                    serversProvider: { appStateManager.servers },
                    tasksProvider: { appStateManager.allTasks },
                    interval: dashboardAutoRefreshInterval,
                    shouldPauseRefresh: { appStateManager.isRefreshSuspendedForScrolling },
                    remainingPauseCooldownNanoseconds: {
                        appStateManager.remainingRefreshSuspensionCooldownNanoseconds()
                    }
                )
            } else {
                dashboardViewModel.stopAutoRefresh()
            }
        }
    }

    private func isModuleRenderable(_ module: DashboardModuleType) -> Bool {
        switch module {
        case .recentFinished:
            return appStateManager.hasRecentFinishedTasks
        default:
            return true
        }
    }

    private func markStorageAuditVisible() {
        guard showStorageAudit else { return }
        guard !hasActivatedStorageAudit else { return }
        hasActivatedStorageAudit = true
    }

    private func estimatedModuleMinHeight(for module: DashboardModuleType) -> CGFloat {
        switch module {
        case .proPosterWall:
            return 236
        case .liveTraffic:
            return 134
        case .todayTransfer:
            return 244
        case .globalAssets:
            return 200
        case .serverStatus:
            return 176
        case .storageAudit:
            return 162
        case .recentFinished:
            return 176
        }
    }

    @ViewBuilder
    private func moduleContent(for module: DashboardModuleType) -> some View {
        switch module {
        case .proPosterWall:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Poster Wall"), spacing: 6) {
                DashboardProCinemaLayerView(tasks: combinedTorrents)
            }
        case .liveTraffic:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Traffic Monitoring")) {
                DashboardLiveTrafficModuleView(
                    tasks: appStateManager.allTasks,
                    activeServerID: appStateManager.activeServerId,
                    tasksRevision: appStateManager.tasksRevision
                )
            }
        case .todayTransfer:
            DashboardSectionBlock(title: LanguageManager.shared.localized("近期新增")) {
                DashboardTransferBaselineMetaRow(
                    formattedBaselineTime: dashboardViewModel.formattedBaselineTime,
                    onReset: {
                        dashboardViewModel.resetTransferBaseline()
                    }
                )

                DashboardTodayTransferModuleView(
                    recentUploadBytes: dashboardViewModel.recentUploadBytes,
                    recentDownloadBytes: dashboardViewModel.recentDownloadBytes,
                    uploadData: dashboardViewModel.recentUploadData,
                    downloadData: dashboardViewModel.recentDownloadData,
                    isInitialLoading: !appStateManager.hasInitialDataLoaded || !dashboardViewModel.hasLoadedInitialSnapshot,
                    isStatsLoading: dashboardViewModel.isTransferStatsLoading
                )
            }
        case .globalAssets:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Data Aggregation")) {
                if shouldShowStatsSkeleton {
                    DashboardGlobalAssetsSkeletonView()
                } else {
                    DashboardGlobalAssetsModuleView(
                        snapshot: dashboardViewModel.globalSnapshot,
                        isUsingCachedFallback: dashboardViewModel.isUsingCachedFallback
                    )
                }
            }
        case .serverStatus:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Server Status")) {
                if shouldShowServerSkeleton {
                    DashboardServerStatusSkeletonView(serverCount: appStateManager.servers.count)
                } else {
                    DashboardServerStatusModuleView(
                        servers: appStateManager.servers,
                        tasks: appStateManager.allTasks,
                        tasksRevision: appStateManager.tasksRevision
                    )
                }
            }
        case .storageAudit:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Storage Audit")) {
                if shouldShowStatsSkeleton {
                    DashboardStorageAuditSkeletonView(serverCount: appStateManager.servers.count)
                } else {
                    DashboardStorageAuditModuleView(
                        servers: appStateManager.servers,
                        snapshot: dashboardViewModel.globalSnapshot,
                        onFirstAppear: markStorageAuditVisible
                    )
                }
            }
        case .recentFinished:
            DashboardSectionBlock(title: LanguageManager.shared.localized("Recently Finished")) {
                DashboardRecentFinishedModuleView(
                    tasks: appStateManager.displayedTasks,
                    refreshKey: "\(appStateManager.tasksRevision)|\(appStateManager.activeServerId?.uuidString ?? "all")"
                )
            }
        }
    }

    private func beginDragging(_ module: DashboardModuleType) -> NSItemProvider {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)

        draggedModule = module
        highlightedDropTarget = nil
        activeHoverTarget = nil
        return NSItemProvider(object: module.rawValue as NSString)
    }

    private func handleDrop(items: [String], onto target: DashboardModuleType) -> Bool {
        let source = items.first.flatMap(DashboardModuleType.init(rawValue:)) ?? draggedModule
        defer {
            draggedModule = nil
            highlightedDropTarget = nil
            activeHoverTarget = nil
        }

        guard let source else { return false }
        guard source != target else { return true }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            dashboardViewModel.swapModules(source, with: target, availableModules: enabledModules)
        }
        return true
    }

    private func handleDropTargetChanged(isTargeted: Bool, target: DashboardModuleType) {
        guard isTargeted else {
            if highlightedDropTarget == target { highlightedDropTarget = nil }
            if activeHoverTarget == target { activeHoverTarget = nil }
            return
        }

        highlightedDropTarget = target
        guard let source = draggedModule, source != target else { return }
        guard activeHoverTarget != target else { return }

        activeHoverTarget = target
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dashboardViewModel.swapModules(source, with: target, availableModules: enabledModules)
        }
    }
}

private struct DashboardGlobalAssetsSkeletonView: View {
    var body: some View {
        LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                DashboardTile {
                    VStack(alignment: .leading, spacing: 10) {
                        DashboardSkeletonBlock(width: 18, height: 18, cornerRadius: 6)
                        DashboardSkeletonBlock(width: 84, height: 18, cornerRadius: 5)
                        DashboardSkeletonBlock(width: 72, height: 10, cornerRadius: 4)
                    }
                }
            }
        }
    }
}

private struct DashboardServerStatusSkeletonView: View {
    let serverCount: Int

    var body: some View {
        LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
            ForEach(0..<max(serverCount, 2), id: \.self) { _ in
                DashboardTile(minHeight: 118) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            DashboardSkeletonBlock(width: 22, height: 22, cornerRadius: 6)
                            Spacer()
                            DashboardSkeletonBlock(width: 8, height: 8, cornerRadius: 4)
                        }

                        VStack(spacing: 8) {
                            HStack {
                                DashboardSkeletonBlock(width: 64, height: 10, cornerRadius: 4)
                                Spacer()
                                DashboardSkeletonBlock(width: 64, height: 10, cornerRadius: 4)
                            }
                            HStack {
                                DashboardSkeletonBlock(width: 64, height: 10, cornerRadius: 4)
                                Spacer()
                                DashboardSkeletonBlock(width: 52, height: 10, cornerRadius: 4)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardStorageAuditSkeletonView: View {
    let serverCount: Int

    var body: some View {
        LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
            ForEach(0..<max(serverCount, 2), id: \.self) { _ in
                DashboardTile(minHeight: 104) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            DashboardSkeletonBlock(width: 8, height: 8, cornerRadius: 4)
                            DashboardSkeletonBlock(width: 62, height: 12, cornerRadius: 4)
                        }
                        DashboardSkeletonBlock(width: 92, height: 10, cornerRadius: 4)
                        DashboardSkeletonBlock(width: 68, height: 12, cornerRadius: 4)
                    }
                }
            }
        }
    }
}

private struct DashboardSkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.55 : 0.95)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

private struct DashboardModulesDisabledEmptyStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "square.grid.2x2")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 112, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(LanguageManager.shared.localized("Dashboard Is Empty"))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(LanguageManager.shared.localized("Enable modules in Settings to display the data you care about."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
                .minimumScaleFactor(0.8)

            Button(LanguageManager.shared.localized("Go to Settings"), action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .buttonBorderShape(.capsule)
                .font(.headline)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DashboardSectionBlock<Content: View>: View {
    let title: String
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(title: String, spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            content()
        }
    }
}

private struct DashboardTransferBaselineMetaRow: View {
    let formattedBaselineTime: String
    let onReset: () -> Void

    @State private var resetRotation: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formattedBaselineTime)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 0)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 15)) {
                    resetRotation += 360
                }
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(resetRotation))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LanguageManager.shared.localized("重置近期新增基线"))
        }
    }
}
