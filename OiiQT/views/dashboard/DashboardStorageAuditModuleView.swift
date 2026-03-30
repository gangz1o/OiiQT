//
//  DashboardStorageAuditModuleView.swift
//  OiiQT
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

struct DashboardStorageAuditModuleView: View {
    let servers: [ServerConfig]
    let snapshot: GlobalStatsSnapshot
    let onFirstAppear: (() -> Void)?

    @State private var hasTriggeredFirstAppear = false

    var body: some View {
        Group {
            if servers.isEmpty {
                DashboardTile(minHeight: 68) {
                    Text(LanguageManager.shared.localized("No servers configured"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if snapshot.serverStorage.isEmpty {
                DashboardTile(minHeight: 68) {
                    Text(LanguageManager.shared.localized("Syncing server storage information..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
                    ForEach(snapshot.serverStorage) { entry in
                        DashboardStorageServerTile(entry: entry)
                    }
                }
            }
        }
        .onAppear {
            guard !hasTriggeredFirstAppear else { return }
            hasTriggeredFirstAppear = true
            onFirstAppear?()
        }
    }
}

private struct DashboardStorageServerTile: View {
    let entry: DashboardServerStorageEntry

    var body: some View {
        DashboardTile(minHeight: 104) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.connectionState.indicatorColor)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: entry.connectionState)

                    Text(entry.serverName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(entry.defaultSavePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if entry.isOnline, let remaining = entry.remainingSpace {
                    Text(formatStorageSize(remaining))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Text(entry.statusMessage)
                        .font(.caption)
                        .foregroundStyle(entry.connectionState == .offline ? .red : .secondary)
                }
            }
        }
    }
}
