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
    @State private var posterItems: [ProPosterItem] = []
    @State private var showDebugFallback = false
    @State private var currentIndex = 0
    @State private var autoPlayResetToken = UUID()
    @State private var isAutoAdvancing = false
    @State private var dragOffset: CGFloat = 0

    private var refreshKey: String {
        combinedTorrents
            .map { "\($0.id)-\($0.completionDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|")
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
                    let idsKey = displayItems.map(\.id).joined(separator: "|")
                    let cardWidth: CGFloat = 120
                    let spacing: CGFloat = 14
                    let step = cardWidth + spacing
                    let threshold: CGFloat = 40
                    let centeredBaseOffset = (geo.size.width - cardWidth) / 2
                    let trackOffset = centeredBaseOffset - (CGFloat(currentIndex) * step) + dragOffset

                    HStack(spacing: spacing) {
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                            DashboardProPosterCard(item: item)
                                .frame(width: cardWidth, height: 180)
                                .scaleEffect(index == currentIndex ? 1.04 : 0.96)
                                .opacity(index == currentIndex ? 1 : 0.9)
                        }
                    }
                    .offset(x: trackOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.88), value: currentIndex)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let itemCount = displayItems.count
                                guard itemCount > 0 else {
                                    dragOffset = 0
                                    return
                                }

                                var nextIndex = currentIndex
                                if value.translation.width <= -threshold {
                                    nextIndex = min(currentIndex + 1, itemCount - 1)
                                } else if value.translation.width >= threshold {
                                    nextIndex = max(currentIndex - 1, 0)
                                }

                                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                                    currentIndex = nextIndex
                                    dragOffset = 0
                                }
                                autoPlayResetToken = UUID()
                            }
                    )
                    .task(id: "\(idsKey)-\(autoPlayResetToken.uuidString)") {
                        guard !displayItems.isEmpty else { return }
                        currentIndex = min(max(currentIndex, 0), max(displayItems.count - 1, 0))
                        guard displayItems.count > 1 else { return }

                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            guard !Task.isCancelled else { return }
                            isAutoAdvancing = true
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                                currentIndex = (currentIndex + 1) % displayItems.count
                            }
                            isAutoAdvancing = false
                        }
                    }
                    .onChange(of: currentIndex) { _, _ in
                        if !isAutoAdvancing {
                            autoPlayResetToken = UUID()
                        }
                    }
                    .onChange(of: idsKey) { _, _ in
                        currentIndex = min(max(currentIndex, 0), max(displayItems.count - 1, 0))
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
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
