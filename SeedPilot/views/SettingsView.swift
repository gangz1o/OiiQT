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
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false

    // UI 状态
    @State private var showingClearCacheAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingPrivacyPolicySheet = false
    @State private var showingTermsSheet = false
    @State private var cacheSizeString = LanguageManager.shared.localized("Calculating...")
    @State private var settingsPath: [SettingsRoute] = []
    @State private var iCloudSyncStatus = iCloudSyncManager.shared.currentStatus()

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
                    NavigationLink {
                        TrackerAliasListView()
                    } label: {
                        SettingsRowLabel(title: LanguageManager.shared.localized("Tracker Aliases"), systemName: "tag.fill", tint: .purple)
                    }
                    Toggle(isOn: $iCloudSyncEnabled) {
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
                } header: {
                    Text(LanguageManager.shared.localized("Pro Features"))
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
                }
            }
            .onAppear {
                updateCacheSize()
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return String(format: LanguageManager.shared.localized("Last synced: %@"), formatter.string(from: lastTime))
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
}

private struct LegalSection: Identifiable {
    let id: String
    let titleKey: String
    let bodyKey: String
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

private struct PrivacyPolicySheetView: View {
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

private struct TermsOfServiceSheetView: View {
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
