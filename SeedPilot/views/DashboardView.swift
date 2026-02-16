//
//  DashboardView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI
import SwiftData
import Combine

struct DashboardView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext

    // AppStorage Settings
    @AppStorage("enableProDashboardBackground") private var enableProDashboardBackground: Bool = true
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false

    // UI State
    @State private var bannerTasks: [TorrentTask] = []
    @State private var bannerSelection: Int = 0

    // Auto-Loop Timer
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // Computed Visual State
    private var isBannerVisible: Bool {
        enableProDashboardBackground && !bannerTasks.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 1. Smart Hero Banner (Auto-Loop)
                    if isBannerVisible {
                        SmartHeroBanner(tasks: bannerTasks, selection: $bannerSelection)
                            .frame(height: 280)
                            .transition(.opacity.animation(.spring()))
                            .onReceive(timer) { _ in
                                guard !bannerTasks.isEmpty else { return }
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    bannerSelection = (bannerSelection + 1) % bannerTasks.count
                                }
                            }
                    }

                    VStack(spacing: 24) { // Main Content Stack
                        // 2. Glass Stats Grid
                        StatsGrid(appStateManager: appStateManager, isImmersive: isBannerVisible)
                            .offset(y: isBannerVisible ? -40 : 0)

                        // 3. Server Grid (Replacting Engine Card)
                        ServerGrid(appStateManager: appStateManager)
                            .offset(y: isBannerVisible ? -40 : 0)

                        // 4. Poster Wall
                        PosterWall(appStateManager: appStateManager, showTMDB: showTMDBData)
                             .offset(y: isBannerVisible ? -40 : 0)

                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 16)
                    // Add top padding if banner is missing to avoid crowding nav bar
                    .padding(.top, isBannerVisible ? 0 : 16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .edgesIgnoringSafeArea(isBannerVisible ? .top : [])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ServerSelector(appStateManager: appStateManager)
                }
            }
            .onAppear {
                refreshBannerData()
                appStateManager.checkServerStatus()
            }
            .onChange(of: appStateManager.allTasks) { _, _ in
                refreshBannerData()
            }
            .onChange(of: enableProDashboardBackground) { _, _ in
                refreshBannerData()
            }
        }
    }

    private func refreshBannerData() {
        guard enableProDashboardBackground else {
            withAnimation(.spring()) {
                bannerTasks = []
            }
            return
        }

        // Logic: Get recent tasks
        let recent = appStateManager.allTasks.sorted {
            ($0.addedTime ) > ($1.addedTime )
        }
        .prefix(5)
        .map { $0 }

        withAnimation(.spring()) {
            bannerTasks = recent
        }
    }
}

// MARK: - Components

// 1. Smart Hero Banner
struct SmartHeroBanner: View {
    let tasks: [TorrentTask]
    @Binding var selection: Int
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                SmartHeroHeader(task: task)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never)) // Hide dots if we want clean loop, or .automatic
        .background(Color.black)
    }
}

struct SmartHeroHeader: View {
    let task: TorrentTask
    @Environment(\.modelContext) private var modelContext
    @State private var backdropURL: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url = backdropURL {
                    SimpleCachedImage(url: url)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                     Rectangle()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                }
            }
        }
        .task {
            // Fetch Backdrop URL
            if let path = await TMDBService.shared.fetchBackdrop(hash: task.id, name: task.name, context: modelContext) {
                withAnimation {
                    backdropURL = path
                }
            }
        }
    }
}

// 2. Glass Stats Grid
struct StatsGrid: View {
    let appStateManager: AppStateManager
    let isImmersive: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Speed
            GlassStatCell(isImmersive: isImmersive, title: "实时速度", icon: "bolt.horizontal.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    // Download
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)

                        Text(formatBytes(appStateManager.displayedDownloadSpeed))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.blue)
                            .contentTransition(.numericText(value: Double(appStateManager.displayedDownloadSpeed)))

                        Text("/s")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                    }

                    // Upload
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)

                        Text(formatBytes(appStateManager.displayedUploadSpeed))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.green)
                            .contentTransition(.numericText(value: Double(appStateManager.displayedUploadSpeed)))

                        Text("/s")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
            }

            // Seeding
            GlassStatCell(isImmersive: isImmersive, title: "做种概况", icon: "leaf.fill") {
                let count = appStateManager.allTasks.filter({ $0.status == .seeding }).count
                let size = appStateManager.allTasks.reduce(0) { $0 + $1.size }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(count)")
                            .font(.title3.bold())
                            .foregroundStyle(isImmersive ? .white : .primary)
                            .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                        Text("个任务")
                            .font(.caption2)
                            .foregroundStyle(isImmersive ? .white.opacity(0.8) : .secondary)
                            .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                    }

                    Text("\(formatBytes(size))")
                        .font(.subheadline)
                        .foregroundStyle(isImmersive ? .white.opacity(0.9) : .secondary)
                        .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                }
            }

            // Storage
            GlassStatCell(isImmersive: isImmersive, title: "存储空间", icon: "externaldrive.fill") {
                 VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                         Text("200") // Mock
                            .font(.title3.bold())
                            .foregroundStyle(isImmersive ? .white : .primary)
                            .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                         Text("GB")
                            .font(.caption2)
                            .foregroundStyle(isImmersive ? .white.opacity(0.8) : .secondary)
                            .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)

                        Text("/ 1.0 TB")
                           .font(.caption)
                           .foregroundStyle(isImmersive ? .white.opacity(0.6) : .secondary)
                           .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                    }

                    Capsule()
                        .fill(isImmersive ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                        .frame(height: 4)
                        .overlay(
                            Capsule()
                                .fill(isImmersive ? Color.white : Color.blue)
                                .frame(width: 40), // Mock width
                            alignment: .leading
                        )
                        .shadow(color: isImmersive ? .black.opacity(0.5) : .clear, radius: 1)
                }
            }

            // Connection
            GlassStatCell(isImmersive: isImmersive, title: "连接状态", icon: "waveform.path.ecg") {
                 HStack {
                    Circle()
                         .fill(isImmersive ? Color.white : Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: isImmersive ? .black.opacity(0.5) : .clear, radius: 2)

                     Text("正常")
                        .font(.headline.bold())
                         .foregroundStyle(isImmersive ? .white : .primary)
                         .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)
                }
                 Text("15ms")
                    .font(.caption)
                    .foregroundStyle(isImmersive ? .white.opacity(0.7) : .secondary)
                    .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)

            }
        }
        .animation(.spring(), value: appStateManager.displayedDownloadSpeed)
    }
}

struct GlassStatCell<Content: View>: View {
    let isImmersive: Bool
    let title: String
    let icon: String
    let content: () -> Content

    init(isImmersive: Bool, title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.isImmersive = isImmersive
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.bold())
            .foregroundStyle(isImmersive ? .white.opacity(0.7) : .secondary)
            .shadow(color: isImmersive ? .black.opacity(0.8) : .clear, radius: 2)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Background Logic
        .background(
            Group {
                if isImmersive {
                    Rectangle()
                        .fill(.ultraThinMaterial) // Base Glass
                        .overlay(Color.black.opacity(0.4)) // Darker tint for contrast
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground) // Solid White
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
             RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isImmersive ? Color.white.opacity(0.1) : Color.clear, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(isImmersive ? 0.2 : 0.05), radius: 5, x: 0, y: 3)
    }
}

// 3. Server Grid (Horizontal Scroll)
struct ServerGrid: View {
    let appStateManager: AppStateManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appStateManager.servers) { server in
                    ServerGridItem(
                        server: server,
                        isActive: appStateManager.activeServerId == server.id
                    ) {
                        selectServer(server)
                    }
                }
            }
            .padding(.horizontal, 4) // Align visually
            .padding(.vertical, 4) // Shadow space
        }
    }

    private func selectServer(_ server: ServerConfig) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation {
            appStateManager.activeServerId = server.id
        }
    }
}

struct ServerGridItem: View {
    let server: ServerConfig
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Top Row: Logo + Status Dot
                HStack(alignment: .top) {
                    Group {
                        if server.type == .transmission {
                            if UIImage(named: "tr_logo") != nil {
                                Image("tr_logo")
                                    .resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            if UIImage(named: "qb_logo") != nil {
                                Image("qb_logo")
                                    .resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "network")
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .frame(width: 48, height: 48) // Bolder/Larger
                    // .clipShape(Circle()) // If needed

                    Spacer()

                    // Status Dot (Top Right)
                    Circle()
                        .fill(server.statusColor)
                        .frame(width: 8, height: 8)
                }

                Spacer() // Push content to edges

                // Bottom Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline) // Larger/Bolder
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(server.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(width: 160, height: 140) // Wider/Square-ish
            .background(Color(uiColor: isActive ? .secondarySystemGroupedBackground : .tertiarySystemGroupedBackground))
            .background(Color(uiColor: .systemBackground)) // Always clean white if active or not?
            // Actually, keep subtle difference:
        .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 4. Poster Wall (Unchanged Logic, just ensure context passed)
struct PosterWall: View {
    let appStateManager: AppStateManager
    let showTMDB: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近完成", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let recents = appStateManager.allTasks.prefix(10)
                    if recents.isEmpty {
                        Text("暂无数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 150)
                    } else {
                        ForEach(recents) { task in
                            PosterCard(task: task, showTMDB: showTMDB)
                                .frame(width: 100, height: 150)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 20)
            }
        }
    }
}

struct PosterCard: View {
    let task: TorrentTask
    let showTMDB: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var posterURL: URL?

    var body: some View {
        ZStack {
            if showTMDB, let url = posterURL {
                SimpleCachedImage(url: url)
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback / Art
                ZStack {
                    Color(uiColor: .tertiarySystemGroupedBackground) // Darker card
                    VStack {
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(task.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .frame(width: 100, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
        .task(id: showTMDB) {
             if showTMDB {
                if let path = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext) {
                    withAnimation {
                         posterURL = path
                    }
                }
             }
        }
    }
}

// Header Selector
struct ServerSelector: View {
    let appStateManager: AppStateManager

    var body: some View {
        Menu {
            Button {
                appStateManager.activeServerId = nil
            } label: {
                Label("全部服务器", systemImage: "server.rack")
            }
            ForEach(appStateManager.servers) { server in
                Button {
                     appStateManager.activeServerId = server.id
                } label: {
                    Label(server.name, systemImage: "network")
                }
            }
        } label: {
            HStack(spacing: 4) {
                 Text(appStateManager.activeServerName ?? "全部服务器")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle()) // Hit test
        }
    }
}




