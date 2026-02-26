//
//  SettingsView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import Kingfisher
import UIKit

struct SettingsView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    private let dashboardConfig = DashboardConfig.shared

    // 资源管理
    @AppStorage("refreshRate") private var refreshRate: Int = 5
    @AppStorage("rssRefreshInterval") private var rssRefreshInterval: Int = 30

    // 应用设置
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 1.0

    // Pro 功能
    @AppStorage("isProUser") private var isProUser: Bool = false
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @AppStorage("customTMDBApiKey") private var customTMDBApiKey: String = ""
    @AppStorage("enableGlobalTaskAggregation") private var enableGlobalTaskAggregation: Bool = false
    @AppStorage("proDashboardBackgroundEnabled") private var proDashboardBackgroundEnabled: Bool = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false

    // UI 状态
    @State private var showingClearCacheAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingPrivacyPolicySheet = false
    @State private var showingTermsSheet = false
    @State private var showingProRequiredDialog = false
    @State private var showingProPaywallSheet = false
    @State private var showingTMDBAPIKeySettings = false
    @State private var showingTrackerAliasList = false
    @State private var cacheSizeString = LanguageManager.shared.localized("Calculating...")
    @State private var settingsPath: [SettingsRoute] = []
    @State private var iCloudSyncStatus = iCloudSyncManager.shared.currentStatus()
    @State private var hasPerformedInitialLoad = false

    private static let iCloudStatusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private var tmdbAPIKeyStatusText: String {
        guard isProUser else { return "" }
        return customTMDBApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LanguageManager.shared.localized("Recommended")
            : LanguageManager.shared.localized("Configured")
    }

    private var tmdbAPIKeyStatusColor: Color {
        guard isProUser else { return .secondary }
        return customTMDBApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .orange : .secondary
    }

    var body: some View {
        NavigationStack(path: $settingsPath) {
            Form {
                // MARK: - Pro 升级
                Section {
                    NavigationLink {
                        ProView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isProUser ? "checkmark.seal.fill" : "sparkles")
                                .font(.title2)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: isProUser ? [.green, .mint] : [.purple, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    isProUser
                                    ? LanguageManager.shared.localized("SeedPilot Pro Active")
                                    : LanguageManager.shared.localized("Upgrade to SeedPilot Pro")
                                )
                                    .font(.headline)
                                Text(
                                    isProUser
                                    ? LanguageManager.shared.localized("All Pro features unlocked")
                                    : LanguageManager.shared.localized("Unlock TMDB poster wall and dynamic dashboard")
                                )
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

                    NavigationLink {
                        PresetPathsView()
                    } label: {
                        HStack(spacing: 12) {
                            AppleStyleIcon(backgroundColor: .yellow, systemName: "folder.fill")
                            Text(LanguageManager.shared.localized("Preset Save Paths"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
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
                        SettingsRowLabel(title: LanguageManager.shared.localized("RSS Auto Refresh"), systemName: "dot.radiowaves.up.forward", tint: .blue)
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

                    NavigationLink {
                        FontSizeSettingsView()
                    } label: {
                        HStack {
                            SettingsRowLabel(title: LanguageManager.shared.localized("Font Size"), systemName: "textformat.size", tint: .blue)
                            Spacer()
                            Text(fontSizeScaleLabel)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
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
                Section(LanguageManager.shared.localized("Pro Features")) {
                    NavigationLink(value: SettingsRoute.proFeatures) {
                        SettingsRowLabel(
                            title: LanguageManager.shared.localized("Beta Features"),
                            systemName: "sparkles",
                            tint: .purple
                        )
                    }
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
                } footer: {
                    legalFooterView
                }
                .alert(LanguageManager.shared.localized("Cache Cleared"), isPresented: $showingSuccessAlert) {
                    Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Settings"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .dashboardCustomization:
                    DashboardCustomizationView()
                case .proFeatures:
                    proFeaturesSettingsView
                }
            }
            .navigationDestination(isPresented: $showingTrackerAliasList) {
                TrackerAliasListView()
            }
            .navigationDestination(isPresented: $showingTMDBAPIKeySettings) {
                TMDBAPIKeySettingsView()
            }
            .onAppear {
                if !hasPerformedInitialLoad {
                    updateCacheSize()
                    hasPerformedInitialLoad = true
                }
                openPendingSettingsRouteIfNeeded()
                iCloudSyncStatus = iCloudSyncManager.shared.currentStatus()
            }
            .onChange(of: appStateManager.selectedTab) { _, newValue in
                guard newValue == .settings else { return }
                openPendingSettingsRouteIfNeeded()
            }
            .onChange(of: appStateManager.settingsRoute) { _, _ in
                openPendingSettingsRouteIfNeeded()
            }
            .onChange(of: iCloudSyncEnabled) { _, isEnabled in
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                iCloudSyncManager.shared.setSyncEnabled(isEnabled)
                ServerConfigCloudSyncManager.shared.start(with: modelContext)
                ServerConfigCloudSyncManager.shared.handleSyncToggleChanged(enabled: isEnabled)
            }
            .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncStatusDidChange)) { _ in
                iCloudSyncStatus = iCloudSyncManager.shared.currentStatus()
            }
            .sheet(isPresented: $showingPrivacyPolicySheet) {
                PrivacyPolicySheetView()
            }
            .sheet(isPresented: $showingTermsSheet) {
                TermsOfServiceSheetView()
            }
        }
        .alert(
            LanguageManager.shared.localized("Pro Required"),
            isPresented: $showingProRequiredDialog,
        ) {
            Button(LanguageManager.shared.localized("Upgrade to SeedPilot Pro")) {
                showingProPaywallSheet = true
            }
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {}
        } message: {
            Text(LanguageManager.shared.localized("This feature requires SeedPilot Pro."))
        }
        .sheet(isPresented: $showingProPaywallSheet) {
            NavigationStack {
                ProView()
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
    }

    private var proFeaturesSettingsView: some View {
        Form {
            Section {
                proFeaturesSettingsRows
            }
        }
        .navigationTitle(LanguageManager.shared.localized("Pro Features"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var proFeaturesSettingsRows: some View {
        Toggle(isOn: tmdbProBinding) {
            SettingsRowLabel(title: LanguageManager.shared.localized("TMDB Poster Data"), systemName: "film", tint: .purple)
        }

        Button {
            guardProAccess {
                showingTMDBAPIKeySettings = true
            }
        } label: {
            HStack {
                SettingsRowLabel(title: LanguageManager.shared.localized("TMDB API Key"), systemName: "key.fill", tint: .indigo)
                Spacer()
                if isProUser {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if customTMDBApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "hand.thumbsup.fill")
                        }
                        Text(tmdbAPIKeyStatusText)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(tmdbAPIKeyStatusColor)
                    .lineLimit(1)
                }
                Image(systemName: isProUser ? "chevron.right" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)

        Toggle(isOn: globalTaskAggregationProBinding) {
            SettingsRowLabel(title: LanguageManager.shared.localized("全局任务聚合"), systemName: "rectangle.stack.fill", tint: .teal)
        }

        Toggle(isOn: proDashboardProBinding) {
            SettingsRowLabel(title: LanguageManager.shared.localized("Pro Dashboard Background"), systemName: "photo.artframe", tint: .orange)
        }

        Button {
            guardProAccess {
                showingTrackerAliasList = true
            }
        } label: {
            HStack {
                SettingsRowLabel(title: LanguageManager.shared.localized("Tracker Aliases"), systemName: "tag.fill", tint: .purple)
                Spacer()
                Image(systemName: isProUser ? "chevron.right" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)

        Toggle(isOn: iCloudProBinding) {
            HStack(spacing: 12) {
                AppleStyleIcon(backgroundColor: .cyan, systemName: "icloud.fill")
                Text(LanguageManager.shared.localized("iCloud Sync"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }

        if iCloudSyncEnabled {
            HStack(spacing: 8) {
                Image(systemName: iCloudSyncStatusIcon)
                    .font(.caption)
                    .foregroundStyle(iCloudSyncStatusColor)
                Text(iCloudSyncStatusText)
                    .font(.footnote)
                    .foregroundStyle(iCloudSyncStatusColor)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Actions

    private var tmdbProBinding: Binding<Bool> {
        Binding(
            get: { showTMDBData },
            set: { newValue in
                if !newValue {
                    showTMDBData = false
                    return
                }
                guardProAccess {
                    showTMDBData = true
                }
            }
        )
    }

    private var proDashboardProBinding: Binding<Bool> {
        Binding(
            get: { proDashboardBackgroundEnabled },
            set: { newValue in
                if !newValue {
                    proDashboardBackgroundEnabled = false
                    return
                }
                guardProAccess {
                    proDashboardBackgroundEnabled = true
                }
            }
        )
    }

    private var globalTaskAggregationProBinding: Binding<Bool> {
        Binding(
            get: { enableGlobalTaskAggregation },
            set: { newValue in
                if !newValue {
                    enableGlobalTaskAggregation = false
                    return
                }
                guardProAccess {
                    enableGlobalTaskAggregation = true
                }
            }
        )
    }

    private var iCloudProBinding: Binding<Bool> {
        Binding(
            get: { iCloudSyncEnabled },
            set: { newValue in
                if !newValue {
                    iCloudSyncEnabled = false
                    return
                }
                guardProAccess {
                    iCloudSyncEnabled = true
                }
            }
        )
    }

    private func guardProAccess(_ action: () -> Void) {
        if isProUser {
            action()
            return
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        showingProRequiredDialog = true
    }

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

    private var legalFooterView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                privacyPolicyButton
                legalSeparator
                termsButton
                legalSeparator
                versionTextInline
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    privacyPolicyButton
                    legalSeparator
                    termsButton
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                versionTextStacked
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 20)
    }

    private var privacyPolicyButton: some View {
        Button {
            showingPrivacyPolicySheet = true
        } label: {
            Text(LanguageManager.shared.localized("Privacy Policy"))
        }
        .buttonStyle(.plain)
    }

    private var termsButton: some View {
        Button {
            showingTermsSheet = true
        } label: {
            Text(LanguageManager.shared.localized("Terms of Service"))
        }
        .buttonStyle(.plain)
    }

    private var legalSeparator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 12)
    }

    private var versionTextInline: some View {
        Text("SeedPilot \(LanguageManager.shared.localized("v1.0.0 (Build 1)"))")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var versionTextStacked: some View {
        Text("SeedPilot \(LanguageManager.shared.localized("v1.0.0 (Build 1)"))")
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
    }

    private var iCloudSyncStatusText: String {
        if iCloudSyncStatus.isSyncing {
            return LanguageManager.shared.localized("Syncing...")
        }

        if let errorCode = iCloudSyncStatus.lastErrorCode {
            switch errorCode {
            case .accountUnavailable:
                return LanguageManager.shared.localized("Sync failed: iCloud account unavailable.")
            case .quotaExceeded:
                return LanguageManager.shared.localized("Sync failed: iCloud storage quota exceeded.")
            case .unknown:
                return LanguageManager.shared.localized("Sync failed. Please try again later.")
            }
        }

        guard let lastTime = iCloudSyncStatus.lastSuccessfulSync else {
            return LanguageManager.shared.localized("Not synced yet")
        }
        return String(
            format: LanguageManager.shared.localized("Last synced: %@"),
            Self.iCloudStatusDateFormatter.string(from: lastTime)
        )
    }

    private var iCloudSyncStatusColor: Color {
        iCloudSyncStatus.lastErrorCode == nil ? .secondary : .red
    }

    private var iCloudSyncStatusIcon: String {
        if iCloudSyncStatus.isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        if iCloudSyncStatus.lastErrorCode != nil {
            return "exclamationmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var fontSizeScaleLabel: String {
        "\(Int((fontSize * 100).rounded()))%"
    }
}

private struct LegalSection: Identifiable {
    let id: String
    let titleKey: String
    let bodyKey: String
}

private struct FontSizeSettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 1.0
    @ObservedObject private var languageManager = LanguageManager.shared

    private var fontScale: CGFloat { CGFloat(fontSize) }
    private var trackerFontSize: CGFloat { 10 * fontScale }
    private var titleFontSize: CGFloat { 14 * fontScale }
    private var captionFontSize: CGFloat { 11 * fontScale }
    private var bodyPreviewFontSize: CGFloat { 15 * fontScale }

    private var isEnglish: Bool {
        languageManager.selectedLanguage == .english
    }

    private var livePreviewTitle: String {
        isEnglish ? "Live Preview" : "实时预览"
    }

    private var textPreviewTitle: String {
        isEnglish ? "Text Preview" : "文字预览"
    }

    private var textPreviewDescription: String {
        isEnglish
            ? "This area previews regular app text scaling outside task cards."
            : "这里用于预览任务卡片外普通文案的字号变化效果。"
    }

    private var sliderHint: String {
        isEnglish
            ? "Drag the slider to adjust task titles and data text size across the app."
            : "拖动滑块以调整 App 内的任务标题与数据文字大小。"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(livePreviewTitle)
                        .font(.headline)

                    previewCard
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(textPreviewTitle)
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("欢迎使用SeedPilot")
                            .font(.system(size: 20 * fontScale, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text("Welcome to SeedPilot")
                            .font(.system(size: 19 * fontScale, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(textPreviewDescription)
                            .font(.system(size: bodyPreviewFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: fontSize)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading, spacing: 10) {
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

                    Text(sliderHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(LanguageManager.shared.localized("Font Size"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewCard: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.45), Color.cyan.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 65, height: 97.5)
                .overlay(alignment: .topLeading) {
                    DiagonalRibbonView(text: "1080p", color: .blue)
                        .scaleEffect(fontScale, anchor: .topLeading)
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("tracker")
                        .font(.system(size: trackerFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())

                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                        Text("6天10小时40分")
                    }
                    .font(.system(size: captionFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(LanguageManager.shared.localized("Seeding"))
                            .font(.system(size: captionFontSize, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("100%")
                            .font(.system(size: captionFontSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }
                }

                Text("The.Matrix.1999.REMASTERED.2160p.UHD.BluRay.x265.10bit.DTS-HD.MA.5.1".replacingOccurrences(of: ".", with: ".\u{200B}"))
                    .font(.system(size: titleFontSize, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                FontSizePreviewProgressView(
                    progress: 0.72,
                    statusColor: .green,
                    downloadSpeedText: "1.2 MB/s",
                    uploadSpeedText: "256 KB/s",
                    peersText: "4/18",
                    seedsText: "9/73",
                    sizeText: "18.4 GB",
                    ratioText: "1.48",
                    fontSize: captionFontSize
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: fontSize)
    }
}

private struct FontSizePreviewProgressView: View {
    let progress: Double
    let statusColor: Color
    let downloadSpeedText: String
    let uploadSpeedText: String
    let peersText: String
    let seedsText: String
    let sizeText: String
    let ratioText: String
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(statusColor)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: 6) {
                FontSizePreviewGridRow(icon: "arrow.down.circle", text: downloadSpeedText, fontSize: fontSize)
                FontSizePreviewGridRow(icon: "arrow.down", text: peersText, fontSize: fontSize)
                FontSizePreviewGridRow(icon: "doc", text: sizeText, fontSize: fontSize)
                FontSizePreviewGridRow(icon: "arrow.up.circle", text: uploadSpeedText, fontSize: fontSize)
                FontSizePreviewGridRow(icon: "leaf", text: seedsText, fontSize: fontSize)
                FontSizePreviewGridRow(icon: "arrow.left.and.right", text: ratioText, fontSize: fontSize)
            }
        }
    }
}

private struct FontSizePreviewGridRow: View {
    let icon: String
    let text: String
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct LegalDocumentSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let navigationTitleKey: String
    let documentTitleKey: String
    let effectiveDateKey: String
    let sections: [LegalSection]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(LanguageManager.shared.localized(documentTitleKey))
                        .font(.headline)

                    Text(LanguageManager.shared.localized(effectiveDateKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(sections) { section in
                        policySection(titleKey: section.titleKey, bodyKey: section.bodyKey)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(LanguageManager.shared.localized(navigationTitleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LanguageManager.shared.localized("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func policySection(titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.shared.localized(titleKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(LanguageManager.shared.localized(bodyKey))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrivacyPolicySheetView: View {
    private let sections: [LegalSection] = [
        LegalSection(id: "privacy-1", titleKey: "Policy Section Data Scope Title", bodyKey: "Policy Section Data Scope Body"),
        LegalSection(id: "privacy-2", titleKey: "Policy Section Purpose Title", bodyKey: "Policy Section Purpose Body"),
        LegalSection(id: "privacy-3", titleKey: "Policy Section ThirdParty Title", bodyKey: "Policy Section ThirdParty Body"),
        LegalSection(id: "privacy-4", titleKey: "Policy Section LocalStorage Title", bodyKey: "Policy Section LocalStorage Body"),
        LegalSection(id: "privacy-5", titleKey: "Policy Section SecurityNotice Title", bodyKey: "Policy Section SecurityNotice Body"),
        LegalSection(id: "privacy-6", titleKey: "Policy Section Retention Title", bodyKey: "Policy Section Retention Body"),
        LegalSection(id: "privacy-7", titleKey: "Policy Section Controls Title", bodyKey: "Policy Section Controls Body"),
        LegalSection(id: "privacy-8", titleKey: "Policy Section Minors Title", bodyKey: "Policy Section Minors Body"),
        LegalSection(id: "privacy-9", titleKey: "Policy Section Updates Title", bodyKey: "Policy Section Updates Body")
    ]

    var body: some View {
        LegalDocumentSheetView(
            navigationTitleKey: "Privacy Policy",
            documentTitleKey: "SeedPilot Privacy Policy",
            effectiveDateKey: "Legal Effective Date",
            sections: sections
        )
    }
}

struct TermsOfServiceSheetView: View {
    private let sections: [LegalSection] = [
        LegalSection(id: "terms-1", titleKey: "Terms Section Acceptance Title", bodyKey: "Terms Section Acceptance Body"),
        LegalSection(id: "terms-2", titleKey: "Terms Section UserResponsibility Title", bodyKey: "Terms Section UserResponsibility Body"),
        LegalSection(id: "terms-3", titleKey: "Terms Section LawfulUse Title", bodyKey: "Terms Section LawfulUse Body"),
        LegalSection(id: "terms-4", titleKey: "Terms Section ThirdPartyDisclaimer Title", bodyKey: "Terms Section ThirdPartyDisclaimer Body"),
        LegalSection(id: "terms-5", titleKey: "Terms Section Availability Title", bodyKey: "Terms Section Availability Body"),
        LegalSection(id: "terms-6", titleKey: "Terms Section LiabilityLimit Title", bodyKey: "Terms Section LiabilityLimit Body"),
        LegalSection(id: "terms-7", titleKey: "Terms Section Indemnification Title", bodyKey: "Terms Section Indemnification Body"),
        LegalSection(id: "terms-8", titleKey: "Terms Section Suspension Title", bodyKey: "Terms Section Suspension Body"),
        LegalSection(id: "terms-9", titleKey: "Terms Section GoverningLaw Title", bodyKey: "Terms Section GoverningLaw Body"),
        LegalSection(id: "terms-10", titleKey: "Terms Section NoMonitoring Title", bodyKey: "Terms Section NoMonitoring Body"),
        LegalSection(id: "terms-11", titleKey: "Terms Section Compliance Title", bodyKey: "Terms Section Compliance Body"),
        LegalSection(id: "terms-12", titleKey: "Terms Section Updates Title", bodyKey: "Terms Section Updates Body")
    ]

    var body: some View {
        LegalDocumentSheetView(
            navigationTitleKey: "Terms of Service",
            documentTitleKey: "SeedPilot Terms of Service",
            effectiveDateKey: "Legal Effective Date",
            sections: sections
        )
    }
}

private struct DashboardCustomizationView: View {
    private let dashboardConfig = DashboardConfig.shared

    var body: some View {
        Form {
            Section(LanguageManager.shared.localized("Module Toggles")) {
                Toggle(isOn: dashboardConfig.showTodayTransferBinding) {
                    SettingsRowLabel(title: LanguageManager.shared.localized("今日传输统计"), systemName: "chart.pie", tint: .orange)
                }
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

private struct TMDBAPIKeySettingsView: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("customTMDBApiKey") private var customTMDBApiKey: String = ""

    private let tutorialURL = URL(string: "https://www.ugnas.com/tutorial-detail/id-226.html")!

    private var isUsingDefaultKey: Bool {
        customTMDBApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsIconBadge(systemName: "key.fill", tint: .indigo)
                        SecureField(
                            languageManager.localized("Custom TMDB API Key (Optional)"),
                            text: $customTMDBApiKey
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(languageManager.localized("Recommended: Use your own TMDB API Key for a more stable and faster poster loading experience."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isUsingDefaultKey {
                        Text(languageManager.localized("Currently using built-in default service."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(languageManager.localized("Custom API Key configured."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(languageManager.localized("TMDB API Key"))
            }

            Section {
                Link(destination: tutorialURL) {
                    HStack {
                        SettingsRowLabel(
                            title: languageManager.localized("How to Get TMDB API Key"),
                            systemName: "book.fill",
                            tint: .blue
                        )
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text(languageManager.localized("Use your own TMDB API Key to avoid potential rate limits of the shared service as the user base grows."))
            }
        }
        .navigationTitle(languageManager.localized("TMDB API Key"))
        .navigationBarTitleDisplayMode(.inline)
    }
}



#Preview {
    SettingsView()
}
