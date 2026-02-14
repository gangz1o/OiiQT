//
//  SettingsView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppStateManager.self) private var appStateManager

    // 资源管理
    @AppStorage("refreshRate") private var refreshRate: Int = 5

    // 应用设置
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("language") private var language: String = "zh-Hans"
    @AppStorage("fontSize") private var fontSize: Double = 1.0

    // Pro 功能
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @AppStorage("enableProDashboardBackground") private var enableProDashboardBackground: Bool = false

    // UI 状态
    @State private var showingClearCacheAlert = false
    @State private var showingSuccessAlert = false
    @State private var cacheSizeString = "12.4 MB" // Mock

    var body: some View {
        NavigationStack {
            Form {
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

                // MARK: - Pro 功能
                Section {
                    Toggle(isOn: $showTMDBData) {
                        Label("TMDB 海报数据", systemImage: "film")
                    }
                    Toggle(isOn: $enableProDashboardBackground) {
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
                            Text(ByteCountFormatter.string(fromByteCount: Int64(ImageCacheManager.shared.calculateDiskCacheSize()), countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .confirmationDialog("确定要清除所有缓存吗？", isPresented: $showingClearCacheAlert, titleVisibility: .visible) {
                        Button("清除所有缓存", role: .destructive) {
                            clearCache()
                        }
                        Button("取消", role: .cancel) { }
                    } message: {
                        Text("这将删除所有临时文件和网络缓存，不会影响已下载的任务。")
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
        }
        // 应用全局样式
        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
    }

    // MARK: - Actions

    private func clearCache() {
        // 1. 清除 URLCache
        URLCache.shared.removeAllCachedResponses()

        // 2. 清除临时文件 (NSTemporaryDirectory)
        let fileManager = FileManager.default
        if let tempURL = URL(string: NSTemporaryDirectory()) {
            do {
                let tempContents = try fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil)
                for file in tempContents {
                    try? fileManager.removeItem(at: file)
                }
            } catch {
                print("Failed to list temp directory: \(error)")
            }
        }

        // 3. 清除海报缓存 (ImageCacheManager)
        ImageCacheManager.shared.clearCache()

        // Note: We do NOT clear SwiftData metadata (TMDBMatch) as that is considered persistent "Library" data,
        // unless "Reset" is requested. "Clear Cache" usually implies re-downloadable content (images).

        // 4. Update UI
        withAnimation {
            cacheSizeString = "0 KB"
        }
        showingSuccessAlert = true
    }
}



#Preview {
    SettingsView()
        .environment(AppStateManager())
}
