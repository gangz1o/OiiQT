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
    @State private var posterItems: [PosterModel] = []
    @State private var showDebugFallback = false
    @State private var trackIndex = 0
    @State private var dragOffset: CGFloat = 0

    private let slideDuration: Double = 0.32
    private let cardWidth: CGFloat = 120
    private let cardSpacing: CGFloat = 14
    private let dragThreshold: CGFloat = 40

    private var step: CGFloat { cardWidth + cardSpacing }

    private var refreshKey: String {
        tasks
            .map { "\($0.id)-\($0.completionDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|") + "::\(languageManager.selectedLanguage.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !posterItems.isEmpty || showDebugFallback {
                let displayItems = showDebugFallback ? PosterModel.debugPlaceholders : posterItems
                let loopItems = loopedItems(for: displayItems)

                GeometryReader { geo in
                    let idsKey = loopItems.map(\.id).joined(separator: "|")
                    let safeIndex = trackIndex.clamped(to: 0...(max(loopItems.count - 1, 0)))
                    let baseOffset = (geo.size.width - cardWidth) / 2
                    let trackOffset = baseOffset - CGFloat(safeIndex) * step + dragOffset

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: cardSpacing) {
                            ForEach(Array(loopItems.enumerated()), id: \.element.id) { index, loopItem in
                                DashboardProPosterCard(item: loopItem.item)
                                    .frame(width: cardWidth, height: 180)
                                    .scaleEffect(index == safeIndex ? 1.08 : 0.94)
                                    .opacity(index == safeIndex ? 1.0 : 0.9)
                            }
                        }
                        .offset(x: trackOffset)
                        .contentShape(Rectangle())
                    }
                    .scrollDisabled(true)
                    .gesture(dragGesture(displayItems: displayItems, loopItems: loopItems))
                    .task(id: idsKey) {
                        guard !displayItems.isEmpty else { return }
                        trackIndex = displayItems.count > 1 ? 1 : 0
                        dragOffset = 0
                        guard displayItems.count > 1 else { return }
                        let count = displayItems.count

                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            // Use animation completion to snap seamlessly — no Task.sleep guessing
                            withAnimation(.easeInOut(duration: slideDuration)) {
                                trackIndex += 1
                            } completion: {
                                snapIfNeeded(displayCount: count)
                            }
                        }
                    }
                    .onChange(of: idsKey) { _, _ in
                        trackIndex = displayItems.count > 1 ? 1 : 0
                        dragOffset = 0
                    }
                }
                .frame(height: 188)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: refreshKey) {
            await refreshPosters()
        }
    }

    // MARK: - Carousel helpers

    private func dragGesture(displayItems: [PosterModel], loopItems: [LoopPosterItem]) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard displayItems.count > 1 else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { dragOffset = 0 }
                    return
                }

                let safeIndex = trackIndex.clamped(to: 0...(max(loopItems.count - 1, 0)))
                var next = safeIndex
                if value.translation.width <= -dragThreshold      { next += 1 }
                else if value.translation.width >= dragThreshold  { next -= 1 }
                next = next.clamped(to: 0...(max(loopItems.count - 1, 0)))

                let count = displayItems.count
                withAnimation(.easeInOut(duration: slideDuration)) {
                    trackIndex = next
                    dragOffset = 0
                } completion: {
                    snapIfNeeded(displayCount: count)
                }
            }
    }

    /// Instantly teleport from ghost-copy boundary back to the real item.
    /// Called in `withAnimation completion:` so it fires only after the slide fully finishes.
    @MainActor
    private func snapIfNeeded(displayCount: Int) {
        guard displayCount > 1 else { return }
        guard trackIndex == 0 || trackIndex == displayCount + 1 else { return }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            trackIndex = trackIndex == 0 ? displayCount : 1
        }
    }

    @MainActor
    private func refreshPosters() async {
        let latestTorrents = latestOrderedTorrents(from: tasks)
        showDebugFallback = false

        guard !latestTorrents.isEmpty else {
            posterItems = []
            print("Dashboard: No movie torrents with poster found")
            #if DEBUG
            showDebugFallback = true
            #endif
            return
        }

        let resolved = await getLatestUniquePosters(from: latestTorrents)
        posterItems = resolved

        if resolved.isEmpty {
            print("Dashboard: No movie torrents with poster found")
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
    private func getLatestUniquePosters(from torrents: [TorrentTask]) async -> [PosterModel] {
        var result: [PosterModel] = []
        var seenIdentifiers = Set<String>()
        result.reserveCapacity(7)
        seenIdentifiers.reserveCapacity(7)

        for torrent in torrents {
            guard !Task.isCancelled else { return result }

            // Fast pre-filter for obvious non-media files.
            if torrent.name.hasKnownNonMediaExtension { continue }

            guard let posterURL = await TMDBService.shared.fetchPoster(
                hash: torrent.id,
                name: torrent.name,
                context: modelContext
            ) else {
                continue
            }

            guard isValidTMDBPosterURL(posterURL) else { continue }

            let identifier = posterURL.absoluteString.lowercased()
            if seenIdentifiers.contains(identifier) { continue }

            seenIdentifiers.insert(identifier)
            result.append(
                PosterModel(
                    id: identifier,
                    sourceTaskID: torrent.id,
                    posterURL: posterURL
                )
            )

            if result.count == 7 { break }
        }

        return result
    }

    private func isValidTMDBPosterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("image.tmdb.org")
    }

    private func loopedItems(for items: [PosterModel]) -> [LoopPosterItem] {
        guard items.count > 1, let first = items.first, let last = items.last else {
            return items.map { LoopPosterItem(id: $0.id, item: $0) }
        }

        var result: [LoopPosterItem] = []
        result.reserveCapacity(items.count + 2)
        result.append(LoopPosterItem(id: "loop-head-\(last.id)", item: last))
        result.append(contentsOf: items.map { LoopPosterItem(id: $0.id, item: $0) })
        result.append(LoopPosterItem(id: "loop-tail-\(first.id)", item: first))
        return result
    }

}

private struct PosterModel: Identifiable {
    let id: String
    let sourceTaskID: String
    let posterURL: URL?

    static let debugPlaceholders: [PosterModel] = [
        PosterModel(id: "debug-1", sourceTaskID: "debug-1", posterURL: nil),
        PosterModel(id: "debug-2", sourceTaskID: "debug-2", posterURL: nil),
        PosterModel(id: "debug-3", sourceTaskID: "debug-3", posterURL: nil)
    ]
}

private extension PosterModel {
    var isDebugPlaceholder: Bool { posterURL == nil }
}

private struct LoopPosterItem: Identifiable {
    let id: String
    let item: PosterModel
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
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

private struct DashboardProPosterCard: View {
    let item: PosterModel

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
                SimpleCachedImage(url: item.posterURL)
                    .scaledToFill()
                    .frame(width: 120, height: 180)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
    }
}
