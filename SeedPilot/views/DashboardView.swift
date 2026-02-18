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
    @StateObject private var dashboardViewModel = DashboardViewModel()

    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false
    @AppStorage(DashboardConfig.Keys.showRecentFinished) private var showRecentFinished: Bool = true
    @AppStorage(DashboardConfig.Keys.showLiveTraffic) private var showLiveTraffic: Bool = true
    @AppStorage(DashboardConfig.Keys.showGlobalAssets) private var showGlobalAssets: Bool = true
    @AppStorage(DashboardConfig.Keys.showServerStatus) private var showServerStatus: Bool = true
    @AppStorage(DashboardConfig.Keys.showStorageAudit) private var showStorageAudit: Bool = true

    @State private var draggedModule: DashboardModuleType?
    @State private var highlightedDropTarget: DashboardModuleType?
    @State private var activeHoverTarget: DashboardModuleType?

    private var isProCinemaEnabled: Bool {
        proDashboardBackgroundEnabled || UserDefaults.standard.bool(forKey: "proDashboardBackgroundEnabled")
    }

    private var needsGlobalStatsData: Bool {
        showGlobalAssets || showStorageAudit
    }

    private var combinedTorrents: [TorrentTask] {
        appStateManager.allTasks
    }

    private var enabledModules: [DashboardModuleType] {
        var modules: [DashboardModuleType] = []
        if isProCinemaEnabled { modules.append(.proPosterWall) }
        if showLiveTraffic { modules.append(.liveTraffic) }
        if showGlobalAssets { modules.append(.globalAssets) }
        if showServerStatus { modules.append(.serverStatus) }
        if showStorageAudit { modules.append(.storageAudit) }
        if showRecentFinished { modules.append(.recentFinished) }
        return modules
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
                "\($0.id.uuidString)|\($0.type.rawValue)|\($0.address)|\($0.port)|\($0.username)|\($0.rpcPath)|\($0.allowInsecureSSL)"
            }
            .sorted()
            .joined(separator: "||")
    }

    private var layoutAnimationKey: String {
        [
            isProCinemaEnabled ? "1" : "0",
            showLiveTraffic ? "1" : "0",
            showGlobalAssets ? "1" : "0",
            showServerStatus ? "1" : "0",
            showStorageAudit ? "1" : "0",
            showRecentFinished ? "1" : "0",
            dashboardViewModel.moduleOrder.map(\.rawValue).joined(separator: ",")
        ].joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(visibleModules) { module in
                    moduleContent(for: module)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(draggedModule == module ? 0.6 : 1)
                        .scaleEffect(draggedModule == module ? 1.01 : 1)
                        .shadow(
                            color: .black.opacity(draggedModule == module ? 0.16 : 0.04),
                            radius: draggedModule == module ? 14 : 8,
                            x: 0,
                            y: draggedModule == module ? 8 : 4
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
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(globalStatsRefreshKey)|\(needsGlobalStatsData)") {
            if needsGlobalStatsData {
                dashboardViewModel.startAutoRefresh(
                    serversProvider: { appStateManager.servers },
                    tasksProvider: { appStateManager.allTasks }
                )
            } else {
                dashboardViewModel.stopAutoRefresh()
            }
        }
        .onDisappear {
            dashboardViewModel.stopAutoRefresh()
        }
        .onAppear {
            dashboardViewModel.syncModuleOrder(availableModules: enabledModules)
            print("Dashboard: proDashboardBackgroundEnabled=\(proDashboardBackgroundEnabled), resolved=\(isProCinemaEnabled)")
        }
        .onChange(of: enabledModuleKey) { _, _ in
            dashboardViewModel.syncModuleOrder(availableModules: enabledModules)
        }
        .onChange(of: draggedModule) { _, newValue in
            guard newValue == nil else { return }
            highlightedDropTarget = nil
            activeHoverTarget = nil
        }
        .onChange(of: proDashboardBackgroundEnabled) { _, newValue in
            print("Dashboard: proDashboardBackgroundEnabled changed -> \(newValue)")
        }
    }

    private func isModuleRenderable(_ module: DashboardModuleType) -> Bool {
        switch module {
        case .recentFinished:
            return DashboardRecentFinishedModuleView.hasRecentFinishedTasks(in: appStateManager.displayedTasks)
        default:
            return true
        }
    }

    @ViewBuilder
    private func moduleContent(for module: DashboardModuleType) -> some View {
        switch module {
        case .proPosterWall:
            DashboardSectionBlock(title: "海报墙") {
                DashboardProCinemaLayerView(tasks: combinedTorrents)
            }
        case .liveTraffic:
            DashboardSectionBlock(title: "流量监控") {
                DashboardLiveTrafficModuleView(
                    downloadSpeed: appStateManager.displayedDownloadSpeed,
                    uploadSpeed: appStateManager.displayedUploadSpeed
                )
            }
        case .globalAssets:
            DashboardSectionBlock(title: "数据聚合") {
                DashboardGlobalAssetsModuleView(
                    snapshot: dashboardViewModel.globalSnapshot,
                    isUsingCachedFallback: dashboardViewModel.isUsingCachedFallback
                )
            }
        case .serverStatus:
            DashboardSectionBlock(title: "服务器状态") {
                DashboardServerStatusModuleView(
                    servers: appStateManager.servers,
                    tasks: appStateManager.allTasks
                )
            }
        case .storageAudit:
            DashboardSectionBlock(title: "存储审计") {
                DashboardStorageAuditModuleView(
                    servers: appStateManager.servers,
                    snapshot: dashboardViewModel.globalSnapshot
                )
            }
        case .recentFinished:
            DashboardSectionBlock(title: "最近完成") {
                DashboardRecentFinishedModuleView(tasks: appStateManager.displayedTasks)
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

private struct DashboardSectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
    }
}
