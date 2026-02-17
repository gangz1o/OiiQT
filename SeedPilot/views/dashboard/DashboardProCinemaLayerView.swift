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

    private var refreshKey: String {
        tasks
            .map { "\($0.id)-\($0.name)-\($0.completionDate?.timeIntervalSince1970 ?? 0)-\($0.addedTime.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
    }

    private var candidateTasks: [TorrentTask] {
        tasks
            .filter { task in
                !task.name.hasKnownNonMediaExtension
            }
            .sorted {
                let lhsDate = $0.completionDate ?? $0.addedTime
                let rhsDate = $1.completionDate ?? $1.addedTime
                return lhsDate > rhsDate
            }
            .prefix(80)
            .map { $0 }
    }

    var body: some View {
        Group {
            if !posterItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(posterItems.enumerated()), id: \.element.id) { index, item in
                            DashboardProPosterCard(item: item)
                                .rotationEffect(.degrees(Double((index % 5) - 2) * 1.2))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                }
            }
        }
        .task(id: refreshKey) {
            await refreshPosters()
        }
    }

    @MainActor
    private func refreshPosters() async {
        var resolved: [ProPosterItem] = []
        if candidateTasks.isEmpty {
            posterItems = []
            return
        }

        for task in candidateTasks {
            guard !Task.isCancelled else { return }
            if let posterURL = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext) {
                if !resolved.contains(where: { $0.id == task.id }) {
                    resolved.append(ProPosterItem(task: task, posterURL: posterURL))
                    posterItems = resolved
                }
            }
            if resolved.count == 7 { break }
        }
    }
}

private struct ProPosterItem: Identifiable {
    let task: TorrentTask
    let posterURL: URL

    var id: String { task.id }
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
        ZStack(alignment: .bottomLeading) {
            SimpleCachedImage(url: item.posterURL)
                .aspectRatio(contentMode: .fill)

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(item.task.name)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(8)
        }
        .frame(width: 130, height: 195)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
    }
}
