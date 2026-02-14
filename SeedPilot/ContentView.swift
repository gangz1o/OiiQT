//
//  ContentView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: Bindable(appStateManager).selectedTab) {
            // 仪表盘
            DashboardView()
                .tabItem {
                    Label("仪表盘", systemImage: "chart.bar")
                }
                .tag(AppTab.dashboard)

            // 任务
            TransfersView()
                .tabItem {
                    Label("任务", systemImage: "list.bullet")
                }
                .tag(AppTab.transfers)
                .badge(appStateManager.allTasks.filter { $0.status == .downloading }.count)

            // 自动化
            RSSView()
                .tabItem {
                    Label("自动化", systemImage: "dot.radiowaves.up.forward")
                }
                .tag(AppTab.rss)

            // 管理 (设置)
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        // iOS 17 默认 TabView 已具有磨砂玻璃效果，
        // 使用 .toolbarBackground 显式指定可以确保在所有视图下的一致性
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial) // 磨砂玻璃效果
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            // 加载数据
            appStateManager.loadServers(context: modelContext)
        }
    }
}

#Preview {
    ContentView()
}
