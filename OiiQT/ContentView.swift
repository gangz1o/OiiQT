//
//  ContentView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var rssSources: [RSSFeedSource]
    @AppStorage("refreshRate") private var refreshRate: Int = 5
    @AppStorage("rssRefreshInterval") private var rssRefreshInterval: Int = 30
    @ObservedObject private var dashboardViewModel: DashboardViewModel

    private var shouldShowSubscriptionsTab: Bool {
        !appStateManager.servers.isEmpty
    }

    init(dashboardViewModel: DashboardViewModel) {
        self.dashboardViewModel = dashboardViewModel
    }

    var body: some View {
        TabView(selection: Bindable(appStateManager).selectedTab) {
            // 仪表盘
            DashboardView(viewModel: dashboardViewModel)
                .tabItem {
                    Label(LanguageManager.shared.localized("Dashboard"), systemImage: "chart.bar")
                }
                .tag(AppTab.dashboard)

            // 任务
            TransfersView()
                .tabItem {
                    Label(LanguageManager.shared.localized("Tasks"), systemImage: "list.bullet")
                }
                .tag(AppTab.transfers)
                .badge(appStateManager.downloadingTaskBadgeCount)

            // 自动化
            if shouldShowSubscriptionsTab {
                RSSView()
                    .tabItem {
                        Label(LanguageManager.shared.localized("Automation"), systemImage: "dot.radiowaves.up.forward")
                    }
                    .tag(AppTab.rss)
            }

            if appStateManager.shouldMountMoviePilotTab {
                MoviePilotView()
                    .tabItem {
                        Label(LanguageManager.shared.localized("MoviePilot"), systemImage: "film.stack.fill")
                    }
                    .tag(AppTab.moviePilot)
            }

            // 管理 (设置)
            SettingsView()
                .tabItem {
                    Label(LanguageManager.shared.localized("Settings"), systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .animation(.easeInOut, value: appStateManager.shouldMountMoviePilotTab)
        // iOS 17 默认 TabView 已具有磨砂玻璃效果，
        // 使用 .toolbarBackground 显式指定可以确保在所有视图下的一致性
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            // Splash 启动阶段已完成预加载；仅在独立进入本页时兜底加载
            if appStateManager.servers.isEmpty && !appStateManager.hasInitialDataLoaded {
                appStateManager.loadServers(context: modelContext)
            }
        }
        .onChange(of: rssRefreshInterval) {
            guard scenePhase == .active else { return }
            // Restart timer when setting changes
            RSSMonitor.shared.startAutoRefresh(sources: rssSources, context: modelContext, appStateManager: appStateManager)
        }
        .onChange(of: refreshRate) {
            guard scenePhase == .active else { return }
            appStateManager.startAutoRefresh()
        }
        .onChange(of: rssSources.count) {
            guard scenePhase == .active else { return }
            // Restart timer when sources change
            if rssRefreshInterval > 0 {
                RSSMonitor.shared.startAutoRefresh(sources: rssSources, context: modelContext, appStateManager: appStateManager)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rssFeedSourceCloudSyncDidApply)) { _ in
            guard scenePhase == .active else { return }
            RSSMonitor.shared.startAutoRefresh(sources: rssSources, context: modelContext, appStateManager: appStateManager)
            Task { @MainActor in
                await RSSMonitor.shared.checkFeeds(context: modelContext, appStateManager: appStateManager)
            }
        }
        .task {
            // Start RSS auto-refresh on launch
            RSSMonitor.shared.startAutoRefresh(sources: rssSources, context: modelContext, appStateManager: appStateManager)
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                appStateManager.startAutoRefresh()
                RSSMonitor.shared.startAutoRefresh(sources: rssSources, context: modelContext, appStateManager: appStateManager)
            case .inactive, .background:
                appStateManager.stopAutoRefresh()
                RSSMonitor.shared.stopAutoRefresh()
                dashboardViewModel.stopAutoRefresh()
            @unknown default:
                appStateManager.stopAutoRefresh()
                RSSMonitor.shared.stopAutoRefresh()
                dashboardViewModel.stopAutoRefresh()
            }
        }
        .onChange(of: appStateManager.servers.count) { _, count in
            if count == 0, appStateManager.selectedTab == .rss {
                appStateManager.selectedTab = .transfers
            }
        }
    }
}

@MainActor
private struct ContentViewPreviewHost: View {
    @State private var appStateManager = AppStateManager()
    @StateObject private var dashboardViewModel = DashboardViewModel()

    var body: some View {
        ContentView(dashboardViewModel: dashboardViewModel)
            .environment(appStateManager)
    }
}

#Preview {
    ContentViewPreviewHost()
}
