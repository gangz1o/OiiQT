//
//  DashboardStorageAuditModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

struct DashboardStorageAuditModuleView: View {
    let servers: [ServerConfig]
    let snapshot: GlobalStatsSnapshot

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
    }
}

private struct DashboardStorageServerTile: View {
    let entry: DashboardServerStorageEntry

    var body: some View {
        DashboardTile(minHeight: 104) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

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
                    Text(entry.isOnline ? LanguageManager.shared.localized("Online") : LanguageManager.shared.localized("Connection Error"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
