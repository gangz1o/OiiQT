//
//  SeedPilotApp.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData
import Kingfisher
import UIKit
import Combine

@main
struct SeedPilotApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 1.0
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var launchDashboardViewModel = DashboardViewModel()
    @State private var isAppReady = false

    init() {
        // Configure Kingfisher Image Cache
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024   // 100 MB memory
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024          // 500 MB disk
        cache.diskStorage.config.expiration = .days(7)                  // 7-day expiry

        // Start StoreKit transaction listener as early as possible to avoid
        // missing transactions or triggering runtime warnings on first purchase.
        _ = StoreManager.shared
        iCloudSyncManager.shared.start()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ServerConfig.self,
            TMDBMatch.self,
            RSSFeedSource.self,
            RSSItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var appStateManager = AppStateManager()

    var body: some Scene {
        WindowGroup {
            AppRootView(
                isAppReady: $isAppReady,
                dashboardViewModel: launchDashboardViewModel
            )
                .environment(appStateManager)
                .environment(\.locale, languageManager.currentLocale)
                .environment(\.dynamicTypeSize, appDynamicTypeSize)
                .id(languageManager.selectedLanguage.rawValue)
                .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // Pull any changes made on other devices while this device was backgrounded
                        iCloudSyncManager.shared.refreshFromCloudIfNeeded()
                        Task {
                            await StoreManager.shared.updateCustomerProductStatus()
                        }
                    case .background:
                        // Safety-net push: flush all pending local changes to iCloud
                        // before the OS may suspend the process.
                        iCloudSyncManager.shared.forcePushToCloud()
                    default:
                        break
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private var appDynamicTypeSize: DynamicTypeSize {
        let clamped = min(max(fontSize, 0.8), 1.4)
        switch clamped {
        case ..<0.85:
            return .xSmall
        case ..<0.95:
            return .small
        case ..<1.05:
            return .large
        case ..<1.15:
            return .xLarge
        case ..<1.25:
            return .xxLarge
        default:
            return .xxxLarge
        }
    }
}

private struct AppRootView: View {
    @Binding var isAppReady: Bool
    @ObservedObject var dashboardViewModel: DashboardViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext
    @State private var didStartBootstrap = false

    var body: some View {
        ZStack {
            if isAppReady {
                ContentView(dashboardViewModel: dashboardViewModel)
                    .transition(.opacity)
            } else {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAppReady)
        .task {
            await bootstrapIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            ServerConfigCloudSyncManager.shared.start(with: modelContext)
            ServerConfigCloudSyncManager.shared.reconcileOnLaunchOrBecomeActive()
            RSSFeedSourceCloudSyncManager.shared.start(with: modelContext)
            RSSFeedSourceCloudSyncManager.shared.reconcileOnLaunchOrBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverConfigCloudSyncDidApply)) { _ in
            appStateManager.loadServers(context: modelContext)
        }
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !didStartBootstrap else { return }
        didStartBootstrap = true

        appStateManager.loadServers(context: modelContext)
        ServerCredentialStore.shared.migrateLegacyPasswords(in: modelContext)
        ServerConfigCloudSyncManager.shared.start(with: modelContext)
        ServerConfigCloudSyncManager.shared.reconcileOnLaunchOrBecomeActive()
        RSSFeedSourceCloudSyncManager.shared.start(with: modelContext)
        RSSFeedSourceCloudSyncManager.shared.reconcileOnLaunchOrBecomeActive()
        appStateManager.loadServers(context: modelContext)

        Task { @MainActor in
            await dashboardViewModel.prefetchForLaunch(
                servers: appStateManager.servers,
                tasks: appStateManager.allTasks
            )
        }

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if appStateManager.servers.isEmpty || appStateManager.hasInitialDataLoaded {
                break
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        Task { @MainActor in
            await dashboardViewModel.prefetchForLaunch(
                servers: appStateManager.servers,
                tasks: appStateManager.allTasks
            )
        }

        guard !isAppReady else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            isAppReady = true
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack {
                Spacer()
                appIcon
                    .frame(width: 220, height: 220)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = UIImage(named: "SplashLogo") {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.92), .cyan.opacity(0.86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 7)
        }
    }
}
