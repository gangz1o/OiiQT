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
    @State private var posterItems: [ProPosterItem] = []
    @State private var showDebugFallback = false
    @State private var trackIndex = 1
    @State private var autoPlayResetToken = UUID()
    @State private var dragOffset: CGFloat = 0
    @State private var wrapResetTask: Task<Void, Never>?

    private var refreshKey: String {
        combinedTorrents
            .map { "\($0.id)-\($0.completionDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|") + "::\(languageManager.selectedLanguage.rawValue)"
    }

    private var combinedTorrents: [TorrentTask] { tasks }

    private var candidateTasks: [TorrentTask] {
        combinedTorrents
            .filter { task in
                !task.name.hasKnownNonMediaExtension
            }
            .sorted {
                let lhsDate = $0.completionDate ?? $0.addedTime
                let rhsDate = $1.completionDate ?? $1.addedTime
                return lhsDate > rhsDate
            }
            .prefix(40)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !posterItems.isEmpty || showDebugFallback {
                GeometryReader { geo in
                    let displayItems = showDebugFallback ? ProPosterItem.debugPlaceholders : posterItems
                    let loopItems = loopedItems(for: displayItems)
                    let idsKey = loopItems.map(\.id).joined(separator: "|")
                    let cardWidth: CGFloat = 120
                    let spacing: CGFloat = 14
                    let step = cardWidth + spacing
                    let threshold: CGFloat = 40
                    let slideDuration: Double = 0.32
                    let slideAnimation: Animation = .easeInOut(duration: slideDuration)
                    let centeredBaseOffset = (geo.size.width - cardWidth) / 2
                    let safeTrackIndex = min(max(trackIndex, 0), max(loopItems.count - 1, 0))
                    let trackOffset = centeredBaseOffset - (CGFloat(safeTrackIndex) * step) + dragOffset

                    HStack(spacing: spacing) {
                        ForEach(Array(loopItems.enumerated()), id: \.element.id) { index, loopItem in
                            DashboardProPosterCard(item: loopItem.item)
                                .frame(width: cardWidth, height: 180)
                                .scaleEffect(index == safeTrackIndex ? 1.04 : 0.96)
                                .opacity(index == safeTrackIndex ? 1 : 0.9)
                        }
                    }
                    .offset(x: trackOffset)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                guard !displayItems.isEmpty else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                                        dragOffset = 0
                                    }
                                    return
                                }
                                guard displayItems.count > 1 else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                                        dragOffset = 0
                                    }
                                    return
                                }

                                var nextIndex = safeTrackIndex
                                if value.translation.width <= -threshold {
                                    nextIndex += 1
                                } else if value.translation.width >= threshold {
                                    nextIndex -= 1
                                }
                                nextIndex = min(max(nextIndex, 0), max(loopItems.count - 1, 0))

                                withAnimation(slideAnimation) {
                                    trackIndex = nextIndex
                                    dragOffset = 0
                                }
                                autoPlayResetToken = UUID()
                            }
                    )
                    .task(id: "\(idsKey)-\(autoPlayResetToken.uuidString)") {
                        guard !displayItems.isEmpty else { return }
                        trackIndex = displayItems.count > 1
                            ? min(max(trackIndex, 1), displayItems.count)
                            : 0
                        guard displayItems.count > 1 else { return }

                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(slideAnimation) {
                                trackIndex += 1
                            }
                        }
                    }
                    .onChange(of: trackIndex) { _, newValue in
                        let displayCount = displayItems.count
                        guard displayCount > 1 else { return }
                        wrapResetTask?.cancel()

                        if newValue == 0 {
                            wrapResetTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
                                guard !Task.isCancelled else { return }
                                guard trackIndex == 0 else { return }
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    trackIndex = displayCount
                                }
                            }
                        } else if newValue == displayCount + 1 {
                            wrapResetTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
                                guard !Task.isCancelled else { return }
                                guard trackIndex == displayCount + 1 else { return }
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    trackIndex = 1
                                }
                            }
                        }
                    }
                    .onChange(of: idsKey) { _, _ in
                        trackIndex = displayItems.count > 1 ? 1 : 0
                        autoPlayResetToken = UUID()
                    }
                }
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            print("Dashboard: Pro cinema layer mounted, candidateTasks=\(candidateTasks.count)")
        }
        .onDisappear {
            wrapResetTask?.cancel()
            wrapResetTask = nil
        }
        .task(id: refreshKey) {
            await refreshPosters()
        }
    }

    @MainActor
    private func refreshPosters() async {
        var resolved: [ProPosterItem] = []
        showDebugFallback = false
        guard !candidateTasks.isEmpty else {
            posterItems = []
            print("Dashboard: No movie torrents with poster found")
            #if DEBUG
            showDebugFallback = true
            #endif
            return
        }

        for task in candidateTasks {
            guard !Task.isCancelled else { return }
            if let posterURL = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext) {
                guard isValidTMDBPosterURL(posterURL) else { continue }
                if !resolved.contains(where: { $0.id == task.id }) {
                    resolved.append(ProPosterItem(id: task.id, posterURL: posterURL))
                    // Render immediately once we have a valid poster to avoid waiting for full scan.
                    posterItems = resolved
                }
            }
            if resolved.count == 7 { break }
        }

        posterItems = resolved
        if resolved.isEmpty {
            print("Dashboard: No movie torrents with poster found")
            #if DEBUG
            showDebugFallback = true
            #endif
        }
    }

    private func isValidTMDBPosterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("image.tmdb.org")
    }

    private func loopedItems(for items: [ProPosterItem]) -> [LoopPosterItem] {
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

private struct ProPosterItem: Identifiable {
    let id: String
    let posterURL: URL?

    static let debugPlaceholders: [ProPosterItem] = [
        ProPosterItem(id: "debug-1", posterURL: nil),
        ProPosterItem(id: "debug-2", posterURL: nil),
        ProPosterItem(id: "debug-3", posterURL: nil)
    ]
}

private extension ProPosterItem {
    var isDebugPlaceholder: Bool { posterURL == nil }
}

private struct LoopPosterItem: Identifiable {
    let id: String
    let item: ProPosterItem
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
    let item: ProPosterItem

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
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
