//
//  DashboardServerStatusModuleView.swift
//  OiiQT
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI
import Combine
import UIKit

struct DashboardServerStatusModuleView: View {
    let servers: [ServerConfig]
    let tasks: [TorrentTask]
    let tasksRevision: Int

    @StateObject private var speedViewModel = DashboardServerStatusModuleViewModel()

    var body: some View {
        if !servers.isEmpty {
            LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
                ForEach(servers) { server in
                    DashboardServerStatusTile(
                        server: server,
                        runtimeSpeed: speedViewModel.speedByServerID[server.id] ?? .zero
                    )
                }
            }
            .task(id: tasksRevision) {
                speedViewModel.refreshSpeeds(tasks: tasks)
            }
        }
    }
}

private struct DashboardServerStatusTile: View {
    let server: ServerConfig
    let runtimeSpeed: DashboardServerSpeedSnapshot

    var body: some View {
        DashboardTile(minHeight: 118) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    DashboardCachedServerIconView(type: server.type)
                        .frame(width: 22, height: 22)

                    Text(server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? server.type.rawValue : server.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                        .allowsTightening(true)

                    Spacer(minLength: 8)

                    statusIndicator
                }

                VStack(spacing: 8) {
                    HStack {
                        DashboardServerMetric(
                            icon: "arrow.up",
                            value: "\(formatBytes(runtimeSpeed.uploadSpeed))/s",
                            iconColor: .green
                        )
                        Spacer(minLength: 8)
                        DashboardServerMetric(
                            icon: "arrow.down",
                            value: "\(formatBytes(runtimeSpeed.downloadSpeed))/s",
                            iconColor: .blue
                        )
                    }

                    HStack {
                        DashboardServerMetric(
                            icon: "shippingbox",
                            value: formatStorageSize(server.totalSeedingSize),
                            iconColor: .secondary
                        )
                        Spacer(minLength: 8)
                        DashboardServerMetric(
                            icon: "chart.line.uptrend.xyaxis",
                            value: String(format: "%.2f", server.totalRatio),
                            iconColor: .secondary
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Group {
            switch server.connectionState {
            case .online:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            case .offline:
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            case .pending:
                ProgressView()
                    .controlSize(.mini)
                    .tint(.orange)
                    .frame(width: 10, height: 10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: server.connectionState)
    }
}

private struct DashboardCachedServerIconView: View {
    let type: ServerType

    @State private var cachedIcon: UIImage?

    private var cacheKey: String {
        switch type {
        case .qBittorrent:
            return "dashboard.server.icon.qb"
        case .transmission:
            return "dashboard.server.icon.tr"
        }
    }

    var body: some View {
        Group {
            if let cachedIcon {
                Image(uiImage: cachedIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIcon
            }
        }
        .task(id: cacheKey) {
            loadCachedIcon()
        }
    }

    private var fallbackIcon: some View {
        Group {
            switch type {
            case .qBittorrent:
                Image(systemName: "network")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.blue)
            case .transmission:
                Image(systemName: "tray.and.arrow.down.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.orange)
            }
        }
    }

    private func loadCachedIcon() {
        // UIImage(named:) uses the system's internal asset cache — no manual caching needed.
        let assetName: String = type == .qBittorrent ? "qb_logo" : "tr_logo"
        cachedIcon = UIImage(named: assetName)
    }
}

private struct DashboardServerMetric: View {
    let icon: String
    let value: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.bold())
                .foregroundStyle(iconColor)

            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct DashboardServerSpeedSnapshot: Sendable {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    static let zero = DashboardServerSpeedSnapshot(downloadSpeed: 0, uploadSpeed: 0)
}

@MainActor
private final class DashboardServerStatusModuleViewModel: ObservableObject {
    @Published private(set) var speedByServerID: [UUID: DashboardServerSpeedSnapshot] = [:]

    private var speedAggregationTask: Task<Void, Never>?

    deinit {
        speedAggregationTask?.cancel()
    }

    func refreshSpeeds(tasks: [TorrentTask]) {
        speedAggregationTask?.cancel()
        speedAggregationTask = Task { [tasks] in
            let aggregated = await Task.detached(priority: .utility) {
                DashboardServerStatusModuleViewModel.aggregateSpeeds(tasks: tasks)
            }.value

            guard !Task.isCancelled else { return }
            speedByServerID = aggregated
        }
    }

    nonisolated private static func aggregateSpeeds(tasks: [TorrentTask]) -> [UUID: DashboardServerSpeedSnapshot] {
        var result: [UUID: DashboardServerSpeedSnapshot] = [:]
        result.reserveCapacity(max(tasks.count / 6, 1))

        for task in tasks {
            let serverID = task.serverID
            let existingDownload = result[serverID]?.downloadSpeed ?? 0
            let existingUpload = result[serverID]?.uploadSpeed ?? 0
            result[serverID] = DashboardServerSpeedSnapshot(
                downloadSpeed: existingDownload + task.downloadSpeed,
                uploadSpeed: existingUpload + task.uploadSpeed
            )
        }

        return result
    }
}
