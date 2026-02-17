//
//  DashboardServerStatusModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI
import Kingfisher
import UIKit

struct DashboardServerStatusModuleView: View {
    let servers: [ServerConfig]
    let tasks: [TorrentTask]

    private var speedByServerID: [UUID: DashboardServerSpeedSnapshot] {
        Dictionary(grouping: tasks, by: \.serverID).mapValues { serverTasks in
            DashboardServerSpeedSnapshot(
                downloadSpeed: serverTasks.reduce(0) { $0 + $1.downloadSpeed },
                uploadSpeed: serverTasks.reduce(0) { $0 + $1.uploadSpeed }
            )
        }
    }

    var body: some View {
        if !servers.isEmpty {
            LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
                ForEach(servers) { server in
                    DashboardServerStatusTile(
                        server: server,
                        runtimeSpeed: speedByServerID[server.id] ?? .zero
                    )
                }
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
                HStack {
                    DashboardCachedServerIconView(type: server.type)
                        .frame(width: 22, height: 22)

                    Spacer(minLength: 8)

                    Circle()
                        .fill(server.statusColor)
                        .frame(width: 8, height: 8)
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
        let key = cacheKey
        let iconType = type
        if let memoryImage = ImageCache.default.retrieveImageInMemoryCache(forKey: key) {
            cachedIcon = memoryImage
            return
        }

        ImageCache.default.retrieveImage(forKey: key) { result in
            if case .success(let value) = result, let image = value.image {
                Task { @MainActor in
                    cachedIcon = image
                }
                return
            }

            let assetName: String = iconType == .qBittorrent ? "qb_logo" : "tr_logo"
            guard let image = UIImage(named: assetName) else { return }

            ImageCache.default.store(image, forKey: key)
            Task { @MainActor in
                cachedIcon = image
            }
        }
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

private struct DashboardServerSpeedSnapshot {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    static let zero = DashboardServerSpeedSnapshot(downloadSpeed: 0, uploadSpeed: 0)
}
