//
//  DashboardProCinemaLayerView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI
import SwiftData

struct DashboardProCinemaLayerView: View {
    let tasks: [TorrentTask]

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var backdropItems: [BackdropModel] = []
    @State private var showDebugFallback = false
    @State private var currentIndex = 0

    private let slideDuration: Double = 0.32
    private let autoSlideInterval: UInt64 = 5_000_000_000

    private var refreshKey: String {
        tasks
            .map { "\($0.id)-\($0.completionDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|") + "::\(languageManager.selectedLanguage.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !backdropItems.isEmpty || showDebugFallback {
                let displayItems = showDebugFallback ? BackdropModel.debugPlaceholders : backdropItems
                let carouselKey = displayItems.map(\.id).joined(separator: "|")

                TabView(selection: $currentIndex) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        DashboardProBackdropCard(item: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .onChange(of: carouselKey) { _, _ in
                    if currentIndex >= displayItems.count {
                        currentIndex = 0
                    }
                }
                .task(id: carouselKey) {
                    guard !displayItems.isEmpty else {
                        currentIndex = 0
                        return
                    }

                    if currentIndex >= displayItems.count {
                        currentIndex = 0
                    }

                    guard displayItems.count > 1 else { return }

                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: autoSlideInterval)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: slideDuration)) {
                            currentIndex = (currentIndex + 1) % displayItems.count
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: refreshKey) {
            await refreshBackdrops()
        }
    }

    @MainActor
    private func refreshBackdrops() async {
        let latestTorrents = latestOrderedTorrents(from: tasks)
        showDebugFallback = false

        guard !latestTorrents.isEmpty else {
            backdropItems = []
            currentIndex = 0
            print("Dashboard: No movie torrents with backdrop found")
            #if DEBUG
            showDebugFallback = true
            #endif
            return
        }

        let resolved = await getLatestUniqueBackdrops(from: latestTorrents)
        backdropItems = resolved
        currentIndex = resolved.isEmpty ? 0 : min(currentIndex, resolved.count - 1)

        if resolved.isEmpty {
            print("Dashboard: No movie torrents with backdrop found")
            #if DEBUG
            showDebugFallback = true
            #endif
        }
    }

    private func latestOrderedTorrents(from torrents: [TorrentTask]) -> [TorrentTask] {
        torrents.sorted {
            let lhsDate = $0.completionDate ?? $0.addedTime
            let rhsDate = $1.completionDate ?? $1.addedTime
            return lhsDate > rhsDate
        }
    }

    // Input torrents must already be ordered by latest-added/latest-active.
    @MainActor
    private func getLatestUniqueBackdrops(from torrents: [TorrentTask]) async -> [BackdropModel] {
        var result: [BackdropModel] = []
        var seenTMDBIDs = Set<Int>()
        result.reserveCapacity(7)
        seenTMDBIDs.reserveCapacity(7)

        for torrent in torrents {
            guard !Task.isCancelled else { return result }

            // Fast pre-filter for obvious non-media files.
            if torrent.name.hasKnownNonMediaExtension { continue }

            // TMDB 无结果视为非影视/不可匹配资源，直接跳过。
            guard let details = await TMDBService.shared.fetchDetails(
                hash: torrent.hash,
                name: torrent.name,
                context: modelContext
            ) else {
                continue
            }

            guard let backdropPath = details.backdropPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !backdropPath.isEmpty,
                  let backdropURL = URL(string: "https://image.tmdb.org/t/p/w780" + backdropPath) else {
                continue
            }

            guard isValidTMDBBackdropURL(backdropURL) else { continue }
            if seenTMDBIDs.contains(details.id) { continue }

            seenTMDBIDs.insert(details.id)
            result.append(
                BackdropModel(
                    id: "tmdb-\(details.id)",
                    sourceTaskID: torrent.id,
                    taskName: torrent.name,
                    tmdbID: details.id,
                    backdropURL: backdropURL
                )
            )

            if result.count == 7 { break }
        }

        return result
    }

    private func isValidTMDBBackdropURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("image.tmdb.org")
    }

}

private struct BackdropModel: Identifiable {
    let id: String
    let sourceTaskID: String
    let taskName: String
    let tmdbID: Int
    let backdropURL: URL?

    static let debugPlaceholders: [BackdropModel] = [
        BackdropModel(id: "debug-1", sourceTaskID: "debug-1", taskName: "", tmdbID: -1, backdropURL: nil),
        BackdropModel(id: "debug-2", sourceTaskID: "debug-2", taskName: "", tmdbID: -2, backdropURL: nil),
        BackdropModel(id: "debug-3", sourceTaskID: "debug-3", taskName: "", tmdbID: -3, backdropURL: nil)
    ]
}

private extension BackdropModel {
    var isDebugPlaceholder: Bool { backdropURL == nil }
}

private extension String {
    var hasKnownNonMediaExtension: Bool {
        let ext = (self as NSString).pathExtension.lowercased()
        if ext.isEmpty { return false }
        let excluded: Set<String> = [
            "zip", "rar", "7z", "tar", "gz", "bz2",
            "iso", "img", "dmg",
            "exe", "msi", "pkg", "app", "deb", "rpm",
            "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md"
        ]
        return excluded.contains(ext)
    }
}

private struct DashboardProBackdropCard: View {
    let item: BackdropModel

    var body: some View {
        ZStack {
            if item.isDebugPlaceholder {
                SeedPilotPlaceholder()
                    .overlay {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            } else {
                SimpleCachedImage(url: item.backdropURL)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 性能优化：shadow 应用在纯背景形状上，避免对海报图片做 alpha 遮罩计算
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clear)
                .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
        )
    }
}
