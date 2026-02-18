//
//  SeedPilotApp.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData
import Kingfisher

@main
struct SeedPilotApp: App {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize") private var fontSize: Double = 1.0
    @StateObject private var languageManager = LanguageManager.shared

    init() {
        // Configure Kingfisher Image Cache
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024   // 100 MB memory
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024          // 500 MB disk
        cache.diskStorage.config.expiration = .days(7)                  // 7-day expiry
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
            ContentView()
                .environment(appStateManager)
                .environment(\.locale, languageManager.currentLocale)
                .environment(\.dynamicTypeSize, appDynamicTypeSize)
                .id(languageManager.selectedLanguage.rawValue)
                .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
                .onAppear {
                    // 在 App 启动时通过 MainActor 获取 context 并加载数据
                    // 注意：这里拿不到 View 的 Environment context，
                    // 所以最好是在 ContentView 或者这里创建一个临时的 context (如果不涉及 UI更新)
                    // 但最稳妥的是在 ContentView 的 onAppear 中调用 loadServers
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
