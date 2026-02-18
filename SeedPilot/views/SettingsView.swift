//
//  SettingsView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import Kingfisher

struct SettingsView: View {
    @Environment(AppStateManager.self) private var appStateManager
    private let dashboardConfig = DashboardConfig.shared

    // 资源管理
    @AppStorage("refreshRate") private var refreshRate: Int = 5
    @AppStorage("rssRefreshInterval") private var rssRefreshInterval: Int = 30

    // 应用设置
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("language") private var language: String = "zh-Hans"
    @AppStorage("fontSize") private var fontSize: Double = 1.0

    // Pro 功能
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false

    // UI 状态
    @State private var showingClearCacheAlert = false
    @State private var showingSuccessAlert = false
    @State private var cacheSizeString = "计算中..."
    @State private var settingsPath: [SettingsRoute] = []

    var body: some View {
        NavigationStack(path: $settingsPath) {
            Form {
                // MARK: - Pro 升级
                Section {
                    NavigationLink {
                        ProView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("升级到 SeedPilot Pro")
                                    .font(.headline)
                                Text("解锁 TMDB 海报墙与动态仪表盘")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("查看")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - 资源管理
                Section {
                    NavigationLink {
                        ServerListView()
                    } label: {
                        SettingsRowLabel(title: "服务器设置", systemName: "server.rack", tint: .indigo)
                    }

                    Picker(selection: $refreshRate) {
                        Text("5秒").tag(5)
                        Text("15秒").tag(15)
                        Text("30秒").tag(30)
                        Text("手动").tag(0)
                    } label: {
                        SettingsRowLabel(title: "数据刷新频率", systemName: "arrow.clockwise", tint: .blue)
                    }

                    Picker(selection: $rssRefreshInterval) {
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("关闭自动刷新").tag(0)
                    } label: {
                        SettingsRowLabel(title: "RSS 自动刷新", systemName: "antenna.radiowaves.left.and.right", tint: .blue)
                    }
                } header: {
                    Text("资源管理")
                }

                // MARK: - 应用设置
                Section {
                    Picker(selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    } label: {
                        SettingsRowLabel(title: "外观主题", systemName: "paintpalette.fill", tint: .blue)
                    }

                    Picker(selection: $language) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    } label: {
                        SettingsRowLabel(title: "应用语言", systemName: "globe", tint: .blue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SettingsRowLabel(title: "字体大小", systemName: "textformat.size", tint: .blue)
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                                .foregroundStyle(.secondary)
                            Slider(value: $fontSize, in: 0.8...1.4, step: 0.1)
                            Image(systemName: "textformat.size.larger")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("应用设置")
                }

                Section("仪表盘定制") {
                    NavigationLink {
                        DashboardCustomizationView()
                    } label: {
                        SettingsRowLabel(title: "模块展示", systemName: "square.grid.2x2", tint: .blue)
                    }
                }

                // MARK: - Pro 功能
                Section {
                    Toggle(isOn: $showTMDBData) {
                        SettingsRowLabel(title: "TMDB 海报数据", systemName: "film", tint: .purple)
                    }
                    Toggle(isOn: $proDashboardBackgroundEnabled) {
                        SettingsRowLabel(title: "Pro 仪表盘背景", systemName: "photo.artframe", tint: .orange)
                    }
                } header: {
                    Text("Pro 功能")
                } footer: {
                    Text("开启后将在种子列表中显示影视海报信息")
                }

                // MARK: - 存储与维护
                Section {
                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        HStack {
                            SettingsRowLabel(title: "清除缓存", systemName: "trash", tint: .red)
                            Spacer()
                            Text(cacheSizeString)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .confirmationDialog("确定要清除所有缓存吗？", isPresented: $showingClearCacheAlert, titleVisibility: .visible) {
                        Button("清除所有缓存", role: .destructive) {
                            clearCache()
                        }
                        Button("取消", role: .cancel) { }
                    } message: {
                        Text("这将删除所有临时文件和图片缓存，不会影响已下载的任务。")
                    }
                } header: {
                    Text("存储与维护")
                }
                .alert("缓存已清除", isPresented: $showingSuccessAlert) {
                    Button("好的", role: .cancel) { }
                }

                // MARK: - 关于
                Section {
                    HStack {
                        Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("SeedPilot")
                                .font(.headline)
                            Text("v1.0.0 (Build 1)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)

                    Link(destination: URL(string: "https://github.com/gangz1o/SeedPilot")!) {
                        SettingsRowLabel(title: "GitHub 开源地址", systemName: "link", tint: .gray)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .dashboardCustomization:
                    DashboardCustomizationView()
                }
            }
            .onAppear {
                updateCacheSize()
                openPendingSettingsRouteIfNeeded()
            }
            .onChange(of: appStateManager.selectedTab) { _, newValue in
                guard newValue == .settings else { return }
                openPendingSettingsRouteIfNeeded()
            }
            .onChange(of: appStateManager.settingsRoute) { _, _ in
                openPendingSettingsRouteIfNeeded()
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
    }

    // MARK: - Actions

    private func updateCacheSize() {
        ImageCache.default.calculateDiskStorageSize { result in
            Task { @MainActor in
                if case .success(let size) = result {
                    cacheSizeString = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                }
            }
        }
    }

    private func clearCache() {
        // 1. Clear Kingfisher image cache (memory + disk)
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache {
            Task { @MainActor in
                // 2. Clear URLCache (for any non-image network responses)
                URLCache.shared.removeAllCachedResponses()

                // 3. Clear temp files
                let fileManager = FileManager.default
                if let tempURL = URL(string: NSTemporaryDirectory()) {
                    if let tempContents = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) {
                        for file in tempContents {
                            try? fileManager.removeItem(at: file)
                        }
                    }
                }

                // 4. Update UI
                withAnimation {
                    cacheSizeString = "0 KB"
                }
                showingSuccessAlert = true
            }
        }
    }

    private func openPendingSettingsRouteIfNeeded() {
        guard appStateManager.selectedTab == .settings else { return }
        guard let route = appStateManager.settingsRoute else { return }
        settingsPath = [route]
        appStateManager.settingsRoute = nil
    }
}

private struct DashboardCustomizationView: View {
    private let dashboardConfig = DashboardConfig.shared

    var body: some View {
        Form {
            Section("模块开关") {
                Toggle(isOn: dashboardConfig.showRecentFinishedBinding) {
                    SettingsRowLabel(title: "最近完成 (Recent Finished)", systemName: "clock.arrow.circlepath", tint: .teal)
                }
                Toggle(isOn: dashboardConfig.showLiveTrafficBinding) {
                    SettingsRowLabel(title: "流量监控 (Live Traffic)", systemName: "arrow.left.arrow.right.circle", tint: .blue)
                }
                Toggle(isOn: dashboardConfig.showGlobalAssetsBinding) {
                    SettingsRowLabel(title: "资产总览 (Global Assets)", systemName: "chart.bar.doc.horizontal", tint: .mint)
                }
                Toggle(isOn: dashboardConfig.showServerStatusBinding) {
                    SettingsRowLabel(title: "服务器状态 (Server Status)", systemName: "server.rack", tint: .indigo)
                }
                Toggle(isOn: dashboardConfig.showStorageAuditBinding) {
                    SettingsRowLabel(title: "存储审计 (Storage Audit)", systemName: "externaldrive", tint: .green)
                }
            }
        }
        .navigationTitle("仪表盘定制")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemName: systemName, tint: tint)
            Text(title)
        }
    }
}

private struct SettingsIconBadge: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.96), tint.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}



#Preview {
    SettingsView()
}
