//
//  SeedPilotApp.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

@main
struct SeedPilotApp: App {
    @AppStorage("appearance") private var appearance: String = "system"

    init() {
        // Configure Native URLCache (50MB memory, 500MB disk)
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 500 * 1024 * 1024, diskPath: "seedpilot_images")
        URLCache.shared = cache
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
}
