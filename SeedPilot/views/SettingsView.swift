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
    @ObservedObject private var languageManager = LanguageManager.shared
    private let dashboardConfig = DashboardConfig.shared

    // 资源管理
    @AppStorage("refreshRate") private var refreshRate: Int = 5
    @AppStorage("rssRefreshInterval") private var rssRefreshInterval: Int = 30

    // 应用设置
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 1.0

    // Pro 功能
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false

    // UI 状态
    @State private var showingClearCacheAlert = false
    @State private var showingSuccessAlert = false
    @State private var cacheSizeString = LanguageManager.shared.localized("Calculating...")
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
                                Text(LanguageManager.shared.localized("Upgrade to SeedPilot Pro"))
                                    .font(.headline)
                                Text(LanguageManager.shared.localized("Unlock TMDB poster wall and dynamic dashboard"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(LanguageManager.shared.localized("View"))
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
                        SettingsRowLabel(title: LanguageManager.shared.localized("Server Settings"), systemName: "server.rack", tint: .indigo)
                    }

                    Picker(selection: $refreshRate) {
                        Text(LanguageManager.shared.localized("5s")).tag(5)
                        Text(LanguageManager.shared.localized("15s")).tag(15)
                        Text(LanguageManager.shared.localized("30s")).tag(30)
                        Text(LanguageManager.shared.localized("Manual")).tag(0)
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Data Refresh Rate"), systemName: "arrow.clockwise", tint: .blue)
                    }

                    Picker(selection: $rssRefreshInterval) {
                        Text(LanguageManager.shared.localized("5 min")).tag(5)
                        Text(LanguageManager.shared.localized("15 min")).tag(15)
                        Text(LanguageManager.shared.localized("30 min")).tag(30)
                        Text(LanguageManager.shared.localized("1 hour")).tag(60)
                        Text(LanguageManager.shared.localized("2 hours")).tag(120)
                        Text(LanguageManager.shared.localized("Auto Refresh Off")).tag(0)
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("RSS Auto Refresh"), systemName: "antenna.radiowaves.left.and.right", tint: .blue)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Resources"))
                }

                // MARK: - 应用设置
                Section {
                    Picker(selection: $appearance) {
                        Text(LanguageManager.shared.localized("System")).tag("system")
                        Text(LanguageManager.shared.localized("Light")).tag("light")
                        Text(LanguageManager.shared.localized("Dark")).tag("dark")
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Appearance"), systemName: "paintpalette.fill", tint: .blue)
                    }

                    Picker(selection: languageManager.languageCodeBinding) {
                        Text(LanguageManager.shared.localized("Simplified Chinese")).tag(LanguageManager.SupportedLanguage.simplifiedChinese.rawValue)
                        Text(LanguageManager.shared.localized("English")).tag(LanguageManager.SupportedLanguage.english.rawValue)
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Language"), systemName: "globe", tint: .blue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Font Size"), systemName: "textformat.size", tint: .blue)
                        HStack {
                            Text("A")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: $fontSize, in: 0.8...1.4, step: 0.1)
                                .accessibilityLabel(LanguageManager.shared.localized("Font Size"))
                            Text("A")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(LanguageManager.shared.localized("App Settings"))
                }

                Section(LanguageManager.shared.localized("Dashboard Customization")) {
                    NavigationLink {
                        DashboardCustomizationView()
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Module Visibility"), systemName: "square.grid.2x2", tint: .blue)
                    }
                }

                // MARK: - Pro 功能
                Section {
                    Toggle(isOn: $showTMDBData) {
                        SettingsRowLabel(title: LanguageManager.shared.localized("TMDB Poster Data"), systemName: "film", tint: .purple)
                    }
                    Toggle(isOn: $proDashboardBackgroundEnabled) {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Pro Dashboard Background"), systemName: "photo.artframe", tint: .orange)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Pro Features"))
                } footer: {
                    Text(LanguageManager.shared.localized("Show movie and TV poster information in the torrent list when enabled."))
                }

                // MARK: - 存储与维护
                Section {
                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        HStack {
                            SettingsRowLabel(title: LanguageManager.shared.localized("Clear Cache"), systemName: "trash", tint: .red)
                            Spacer()
                            Text(cacheSizeString)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .confirmationDialog(LanguageManager.shared.localized("Are you sure you want to clear all cache?"), isPresented: $showingClearCacheAlert, titleVisibility: .visible) {
                        Button(LanguageManager.shared.localized("Clear All Cache"), role: .destructive) {
                            clearCache()
                        }
                        Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
                    } message: {
                        Text(LanguageManager.shared.localized("This will delete all temporary files and image cache, without affecting downloaded tasks."))
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Storage & Maintenance"))
                }
                .alert(LanguageManager.shared.localized("Cache Cleared"), isPresented: $showingSuccessAlert) {
                    Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
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
                            Text(LanguageManager.shared.localized("v1.0.0 (Build 1)"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)

                    Link(destination: URL(string: "https://github.com/gangz1o/SeedPilot")!) {
                        SettingsRowLabel(title: LanguageManager.shared.localized("GitHub Repository"), systemName: "link", tint: .gray)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("About"))
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Settings"))
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
            Section(LanguageManager.shared.localized("Module Toggles")) {
                Toggle(isOn: dashboardConfig.showRecentFinishedBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("Recently Finished"), systemName: "clock.arrow.circlepath", tint: .teal)
                }
                Toggle(isOn: dashboardConfig.showLiveTrafficBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("Traffic Monitoring"), systemName: "arrow.left.arrow.right.circle", tint: .blue)
                }
                Toggle(isOn: dashboardConfig.showGlobalAssetsBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("Data Aggregation"), systemName: "chart.bar.doc.horizontal", tint: .mint)
                }
                Toggle(isOn: dashboardConfig.showServerStatusBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("Server Status"), systemName: "server.rack", tint: .indigo)
                }
                Toggle(isOn: dashboardConfig.showStorageAuditBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("Storage Audit"), systemName: "externaldrive", tint: .green)
                }
            }
        }
        .navigationTitle(LanguageManager.shared.localized("Dashboard Customization"))
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
