//
//  DashboardView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @StateObject private var dashboardViewModel = DashboardViewModel()

    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false
    @AppStorage(DashboardConfig.Keys.showRecentFinished) private var showRecentFinished: Bool = true
    @AppStorage(DashboardConfig.Keys.showLiveTraffic) private var showLiveTraffic: Bool = true
    @AppStorage(DashboardConfig.Keys.showGlobalAssets) private var showGlobalAssets: Bool = true
    @AppStorage(DashboardConfig.Keys.showServerStatus) private var showServerStatus: Bool = true

    private var needsGlobalStatsData: Bool {
        showGlobalAssets
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
            proDashboardBackgroundEnabled ? "1" : "0",
            showLiveTraffic ? "1" : "0",
            showGlobalAssets ? "1" : "0",
            showServerStatus ? "1" : "0",
            showRecentFinished ? "1" : "0"
        ].joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if proDashboardBackgroundEnabled {
                    DashboardProCinemaLayerView(tasks: appStateManager.allTasks)
                }

                if showLiveTraffic {
                    DashboardSectionBlock(title: "流量监控") {
                        DashboardLiveTrafficModuleView(
                            downloadSpeed: appStateManager.displayedDownloadSpeed,
                            uploadSpeed: appStateManager.displayedUploadSpeed
                        )
                    }
                }

                if showGlobalAssets {
                    DashboardSectionBlock(title: "数据聚合") {
                        DashboardGlobalAssetsModuleView(
                            snapshot: dashboardViewModel.globalSnapshot,
                            isUsingCachedFallback: dashboardViewModel.isUsingCachedFallback
                        )
                    }
                }

                if showServerStatus {
                    DashboardSectionBlock(title: "服务器状态") {
                        DashboardServerStatusModuleView(
                            servers: appStateManager.servers,
                            tasks: appStateManager.allTasks
                        )
                    }
                }

                if showRecentFinished && DashboardRecentFinishedModuleView.hasRecentFinishedTasks(in: appStateManager.displayedTasks) {
                    DashboardSectionBlock(title: "最近完成") {
                        DashboardRecentFinishedModuleView(tasks: appStateManager.displayedTasks)
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
