//
//  DashboardView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI
import Charts
import SwiftData
import Combine

struct DashboardView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("enableProDashboardBackground") private var enableProDashboardBackground: Bool = false

    // UI State
    @State private var bannerIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // Background Layer (Subtle Gradient)
                LinearGradient(
                    colors: [Color(uiColor: .systemGroupedBackground), Color(uiColor: .systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Main Content
                ScrollView {
                    VStack(spacing: 24) {
                        // 1. Pro Banner (Sliding Header)
                        if enableProDashboardBackground {
                            proBannerSection
                        } else {
                            // Fallback welcome or static banner
                            staticWelcomeBanner
                        }

                        // 2. Speed Indicators (Compact Header)
                        speedHeaderSection

                        // 3. Server Grid
                        serverTilesSection

                        // 4. Recent Gallery (Smaller)
                        recentItemsSection
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle(appStateManager.activeServerName ?? "仪表盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text(appStateManager.activeServerName ?? "全部服务器")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbarTitleMenu {
                Button {
                    appStateManager.activeServerId = nil
                } label: {
                    Label("全部服务器", systemImage: "server.rack")
                }

                ForEach(appStateManager.servers) { server in
                    Button {
                        appStateManager.activeServerId = server.id
                    } label: {
                        Label(server.name, systemImage: server.type == .qBittorrent ? "network" : "antenna.radiowaves.left.and.right")
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private static let bannerTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var proBannerSection: some View {
        TabView(selection: $bannerIndex) {
            let tasks = getRecentTasks().prefix(5)
            if tasks.isEmpty {
                // Default Pro Banner
                defaultBannerView(title: "SeedPilot Pro", subtitle: "Your Home Command Center")
                    .tag(0)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    ProBannerItem(task: task)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
        .onReceive(Self.bannerTimer) { _ in
            let count = min(getRecentTasks().count, 5)
            guard count > 1 else { return }
            withAnimation {
                bannerIndex = (bannerIndex + 1) % count
            }
        }
    }

    private var staticWelcomeBanner: some View {
        defaultBannerView(title: "SeedPilot", subtitle: "Dashboard")
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 16)
    }

    private func defaultBannerView(title: String, subtitle: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var speedHeaderSection: some View {
        HStack(spacing: 30) {
            Spacer()

            // Download
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, value: appStateManager.allTasks.reduce(0) { $0 + $1.downloadSpeed })

                Text(torrentByteFormatter.string(fromByteCount: appStateManager.allTasks.reduce(0) { $0 + $1.downloadSpeed }) + "/s")
                    .font(.system(.title2, design: .rounded).monospacedDigit().bold())
            }

            // Upload
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: appStateManager.allTasks.reduce(0) { $0 + $1.uploadSpeed })

                Text(torrentByteFormatter.string(fromByteCount: appStateManager.allTasks.reduce(0) { $0 + $1.uploadSpeed }) + "/s")
                    .font(.system(.title2, design: .rounded).monospacedDigit().bold())
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var serverTilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("服务器", systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(appStateManager.servers) { server in
                    Button {
                        selectServer(server)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: server.type == .qBittorrent ? "network" : "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                Spacer()
                                Circle()
                                    .fill(server.isOnline == true ? Color.green : (server.isOnline == false ? Color.red : Color.gray))
                                    .frame(width: 6, height: 6)
                            }

                            Spacer()

                            Text(server.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            Spacer()

                            // Mock Progress
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 3)
                                .overlay(
                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.blue)
                                            .frame(width: geo.size.width * 0.45)
                                    },
                                    alignment: .leading
                                )
                        }
                        .padding(12)
                        .aspectRatio(1.0, contentMode: .fit)
                        .background(Material.thin)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var recentItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近完成", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    let recents = getRecentTasks()
                    if recents.isEmpty {
                        Text("暂无最近完成的任务")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(recents) { task in
                            Button {
                                // Detail action
                            } label: {
                                PosterThumbnail(task: task)
                                    .frame(width: 80, height: 120) // Smaller posters
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Logic

    private func selectServer(_ server: ServerConfig) {
        withAnimation {
            appStateManager.activeServerId = server.id
            appStateManager.selectedTab = .transfers
        }
    }

    private func getRecentTasks() -> [TorrentTask] {
        let completed = appStateManager.allTasks.filter {
            $0.progress >= 1.0 || $0.status == .completed || $0.status == .seeding
        }
        // Prefer explicit completion date
        return completed.sorted {
            ($0.completionDate ?? Date.distantPast) > ($1.completionDate ?? Date.distantPast)
        }
        .prefix(10)
        .map { $0 }
    }
}

// Pro Banner Helper Component
struct ProBannerItem: View {
    let task: TorrentTask
    @Environment(\.modelContext) private var modelContext
    @State private var backdropURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            if let url = backdropURL {
                CachedAsyncImage(url: url, cacheKey: task.id + "_backdrop.jpg") { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color(.systemGray5)
                        ProgressView()
                    }
                }
            } else {
                // Fallback Gradient
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Gradient Overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                Text(SeedPilotParser.parse(task.name).title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack {
                    Text(task.sizeString)
                    Text("•")
                    Text(task.status.rawValue)
                }
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .padding(.bottom, 10)
        }
        .task {
            if backdropURL == nil {
                backdropURL = await TMDBService.shared.fetchBackdrop(hash: task.id, name: task.name, context: modelContext)
            }
        }
    }
}

// Simple Poster Thumbnail Helper
struct PosterThumbnail: View {
    let task: TorrentTask
    @Environment(\.modelContext) private var modelContext
    @State private var url: URL?

    var body: some View {
        Group {
            if let u = url {
                CachedAsyncImage(url: u, cacheKey: task.id + ".jpg") { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.systemGray5)
                }
            } else {
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if url == nil {
                url = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext)
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
