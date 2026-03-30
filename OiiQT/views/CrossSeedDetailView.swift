//
//  CrossSeedDetailView.swift
//  OiiQT
//

import SwiftUI

// MARK: - CrossSeedDetailView

struct CrossSeedDetailView: View {
    let torrents: [TorrentTask]
    let servers: [ServerConfig]

    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        List {
            Section {
                ForEach(torrents) { torrent in
                    CrossSeedCell(torrent: torrent, servers: servers)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            } header: {
                Text(
                    String(
                        format: languageManager.localized("Cross-Seed Count Format"),
                        torrents.count
                    )
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(languageManager.localized("Cross-Seed Details"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - CrossSeedCell

private struct CrossSeedCell: View {
    let torrent: TorrentTask
    let servers: [ServerConfig]

    private var serverName: String {
        servers.first(where: { $0.id == torrent.serverID })?.name
            ?? LanguageManager.shared.localized("Unknown Server")
    }

    private var statusColor: Color { torrent.status.color }

    private var progressPercent: String {
        String(format: "%.0f%%", torrent.progress * 100)
    }

    private var trackerDisplay: String {
        let host = torrent.trackerHost
        return host.isEmpty || host == "--" ? torrent.savePath : host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Row 1 — Server name (left) + Status (right)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(serverName)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(torrent.status.localizedDisplayName)
                        .font(.caption.bold())
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.1))
                .clipShape(Capsule())
            }

            // Row 2 — Speeds (left) + Progress · Ratio (right)
            HStack {
                // Down speed
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                    Text(formatBytes(torrent.downloadSpeed) + "/s")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.blue)
                }

                // Up speed
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                    Text(formatBytes(torrent.uploadSpeed) + "/s")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 8)

                // Progress · Ratio
                HStack(spacing: 6) {
                    Text(progressPercent)
                        .font(.callout.monospacedDigit().weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(
                        LanguageManager.shared.localized("Ratio") + " " +
                        String(format: "%.2f", torrent.ratio)
                    )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(ratioColor(torrent.ratio))
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    Capsule()
                        .fill(statusColor)
                        .frame(width: geo.size.width * CGFloat(min(max(torrent.progress, 0), 1)), height: 4)
                }
            }
            .frame(height: 4)

            // Row 3 — Tracker / save path (tiny, secondary)
            HStack(spacing: 4) {
                Image(systemName: torrent.trackerHost != "--" ? "antenna.radiowaves.left.and.right" : "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(trackerDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    private func ratioColor(_ ratio: Double) -> Color {
        if ratio >= 1.0 { return .green }
        if ratio >= 0.5 { return .orange }
        return .red
    }
}
