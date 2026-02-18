//
//  SettingsView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import Kingfisher

struct SettingsView: View {
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

    var body: some View {
        NavigationStack {
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
                        Label("服务器设置", systemImage: "server.rack")
                    }

                    Picker(selection: $refreshRate) {
                        Text("5秒").tag(5)
                        Text("15秒").tag(15)
                        Text("30秒").tag(30)
                        Text("手动").tag(0)
                    } label: {
                        Label("数据刷新频率", systemImage: "arrow.clockwise")
                    }

                    Picker(selection: $rssRefreshInterval) {
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("关闭自动刷新").tag(0)
                    } label: {
                        Label("RSS 自动刷新", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } header: {
                    Text("资源管理")
                } footer: {
                    if rssRefreshInterval > 0 {
                        Text("每 \(rssRefreshInterval) 分钟自动检查订阅源更新")
                    } else {
                        Text("已关闭自动刷新，仅支持手动刷新")
                    }
                }

                // MARK: - 应用设置
                Section {
                    Picker(selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    } label: {
                        Label("外观主题", systemImage: "paintpalette")
                    }

                    Picker(selection: $language) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    } label: {
                        Label("应用语言", systemImage: "globe")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("字体大小", systemImage: "textformat.size")
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
                    Toggle("最近完成 (Recent Finished)", isOn: dashboardConfig.showRecentFinishedBinding)
                    Toggle("流量监控 (Live Traffic)", isOn: dashboardConfig.showLiveTrafficBinding)
                    Toggle("资产总览 (Global Assets)", isOn: dashboardConfig.showGlobalAssetsBinding)
                    Toggle("服务器状态 (Server Status)", isOn: dashboardConfig.showServerStatusBinding)
                    Toggle("存储审计 (Storage Audit)", isOn: dashboardConfig.showStorageAuditBinding)
                }

                // MARK: - Pro 功能
                Section {
                    Toggle(isOn: $showTMDBData) {
                        Label("TMDB 海报数据", systemImage: "film")
                    }
                    Toggle(isOn: $proDashboardBackgroundEnabled) {
                        Label("Pro 仪表盘背景", systemImage: "photo.artframe")
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
                            Label("清除缓存", systemImage: "trash")
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
                        Label("GitHub 开源地址", systemImage: "link")
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                updateCacheSize()
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
}



#Preview {
    SettingsView()
}
