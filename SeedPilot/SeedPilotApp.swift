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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ServerConfig.self,
            TMDBMatch.self,
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
