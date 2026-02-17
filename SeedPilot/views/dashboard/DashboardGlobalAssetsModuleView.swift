//
//  DashboardGlobalAssetsModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI
import Kingfisher
import UIKit

struct DashboardGlobalAssetsModuleView: View {
    let snapshot: GlobalStatsSnapshot
    let isUsingCachedFallback: Bool

    var body: some View {
        Group {
            if snapshot.hasConnectionIssue && !isUsingCachedFallback {
                DashboardTile(minHeight: 72) {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text("全部服务器离线，无法汇总统计数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
                    DashboardStatsTile(
                        value: "\(snapshot.totalSeedingCount)",
                        unit: "个",
                        icon: "leaf.fill",
                        iconColor: .green
                    )

                    DashboardStatsTile(
                        value: "\(snapshot.totalDownloadingCount)",
                        unit: "个",
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue
                    )

                    DashboardStatsTile(
                        value: formatBytes(snapshot.totalBandwidth),
                        unit: "/s",
                        icon: "arrow.left.arrow.right.circle.fill",
                        iconColor: .orange
                    )

                    DashboardStatsTile(
                        value: formatStorageSize(snapshot.totalRemainingSpace),
                        unit: "",
                        icon: "externaldrive.fill",
                        iconColor: .mint
                    )
                }
            }
        }
    }
}

private struct DashboardStatsTile: View {
    let value: String
    let unit: String
    let icon: String
    let iconColor: Color

    var body: some View {
        DashboardTile {
            VStack(alignment: .leading, spacing: 10) {
                DashboardCachedSymbolIconView(systemName: icon, tint: iconColor)
                    .frame(width: 18, height: 18)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DashboardCachedSymbolIconView: View {
    let systemName: String
    let tint: Color

    @State private var cachedIcon: UIImage?

    private var cacheKey: String {
        "dashboard.stats.symbol.\(systemName)"
    }

    var body: some View {
        Group {
            if let cachedIcon {
                Image(uiImage: cachedIcon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(tint)
        .task(id: cacheKey) {
            loadCachedIcon()
        }
    }

    private func loadCachedIcon() {
        let key = cacheKey
        let symbolName = systemName

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

            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            guard let generated = UIImage(systemName: symbolName, withConfiguration: config) else { return }

            ImageCache.default.store(generated, forKey: key)
            Task { @MainActor in
                cachedIcon = generated
            }
        }
    }
}
