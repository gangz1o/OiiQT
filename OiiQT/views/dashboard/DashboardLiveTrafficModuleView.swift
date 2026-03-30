//
//  DashboardLiveTrafficModuleView.swift
//  OiiQT
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI
import Combine

struct DashboardLiveTrafficModuleView: View {
    let tasks: [TorrentTask]
    let activeServerID: UUID?
    let tasksRevision: Int

    @StateObject private var trafficViewModel = DashboardTrafficModuleViewModel()

    private var refreshKey: String {
        "\(tasksRevision)|\(activeServerID?.uuidString ?? "all")"
    }

    var body: some View {
        LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
            // 性能优化：使用 EquatableView 包裹，高频速度更新仅触发文本局部刷新
            EquatableView(content: DashboardTrafficTile(
                value: formatBytes(trafficViewModel.downloadSpeed),
                icon: "arrow.down.circle.fill",
                tint: .blue
            ))

            EquatableView(content: DashboardTrafficTile(
                value: formatBytes(trafficViewModel.uploadSpeed),
                icon: "arrow.up.circle.fill",
                tint: .green
            ))
        }
        .task(id: refreshKey) {
            trafficViewModel.refresh(
                tasks: tasks,
                activeServerID: activeServerID
            )
        }
    }
}

// 性能优化：遵循 Equatable，配合 EquatableView 实现状态隔离
private struct DashboardTrafficTile: View, Equatable {
    let value: String
    let icon: String
    let tint: Color

    static func == (lhs: DashboardTrafficTile, rhs: DashboardTrafficTile) -> Bool {
        lhs.value == rhs.value && lhs.icon == rhs.icon && lhs.tint == rhs.tint
    }

    var body: some View {
        DashboardTile {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text("/s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
private final class DashboardTrafficModuleViewModel: ObservableObject {
    @Published private(set) var downloadSpeed: Int64 = 0
    @Published private(set) var uploadSpeed: Int64 = 0

    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func refresh(tasks: [TorrentTask], activeServerID: UUID?) {
        refreshTask?.cancel()
        refreshTask = Task { [tasks, activeServerID] in
            let summary = await Task.detached(priority: .utility) {
                DashboardTrafficModuleViewModel.aggregateSpeed(
                    tasks: tasks,
                    activeServerID: activeServerID
                )
            }.value

            guard !Task.isCancelled else { return }
            downloadSpeed = summary.download
            uploadSpeed = summary.upload
        }
    }

    nonisolated private static func aggregateSpeed(
        tasks: [TorrentTask],
        activeServerID: UUID?
    ) -> (download: Int64, upload: Int64) {
        var totalDownloadSpeed: Int64 = 0
        var totalUploadSpeed: Int64 = 0

        for task in tasks {
            if let activeServerID, task.serverID != activeServerID {
                continue
            }
            totalDownloadSpeed += task.downloadSpeed
            totalUploadSpeed += task.uploadSpeed
        }

        return (download: totalDownloadSpeed, upload: totalUploadSpeed)
    }
}
