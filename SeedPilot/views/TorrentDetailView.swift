//
//  TorrentDetailView.swift
//  SeedPilot
//
//  Created by SeedPilot AI on 2026/2/17.
//

import SwiftUI
import SwiftData

struct TorrentDetailView: View {
    let task: TorrentTask
    var appStateManager: AppStateManager

    @AppStorage("showTMDBData") private var tmdbPosterEnabled: Bool = false
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var tmdbItem: TMDBItem?
    @State private var isLoadingTMDB = false

    // Derived properties
    private var serverName: String {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.name ?? LanguageManager.shared.localized("Unknown Server")
    }

    var body: some View {
        List {
            // MARK: - 1. Header Section
            Section {
                if tmdbPosterEnabled, let item = tmdbItem {
                    // Pro Mode with Match
                    HStack(alignment: .top, spacing: 16) {
                        // Poster (2:3 aspect ratio)
                        if let url = item.fullPosterURL {
                            SimpleCachedImage(url: url)
                                .aspectRatio(2/3, contentMode: .fit)
                                .frame(width: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 100, height: 150)
                                .cornerRadius(8)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.title3.bold())
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                if let rating = item.voteAverage, rating > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption.monospacedDigit().bold())
                                    }
                                }

                                Text(item.year)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }

                            if let overview = item.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            } else {
                                Text(LanguageManager.shared.localized("No Overview"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // Standard Mode / No Match
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(.headline)
                            .lineLimit(3)

                        Text(task.status.localizedDisplayName)
                             .font(.subheadline)
                             .foregroundStyle(task.status.color)
                             .lineLimit(1)
                             .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            // MARK: - 2. Static Data Report (The Static Report)
            Section {
                // 速率 Rate
                HStack {
                    Text(LanguageManager.shared.localized("Rate"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 16) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                            Text(formatBytes(task.downloadSpeed) + "/s")
                        }
                        .foregroundStyle(.blue)

                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                            Text(formatBytes(task.uploadSpeed) + "/s")
                        }
                        .foregroundStyle(.green)
                    }
                    .font(.callout.monospacedDigit())
                }

                // 流量 Traffic
                HStack {
                    Text(LanguageManager.shared.localized("Traffic"))
                         .foregroundStyle(.secondary)
                    Spacer()
                    Text("↓\(task.downloadedString)  ↑\(task.uploadedString)")
                        .font(.callout.monospacedDigit())
                }

                // 管理 Management (Ratio)
                HStack {
                    Text(LanguageManager.shared.localized("Ratio"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", task.ratio))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(ratioColor(task.ratio))
                }

                // 存储 Storage (Save Path)
                HStack {
                    Text(LanguageManager.shared.localized("Save Path"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.savePath)
                        .font(.callout.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled) // Allow copying
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = task.savePath
                            } label: {
                                Label(LanguageManager.shared.localized("Copy Path"), systemImage: "doc.on.doc")
                            }
                        }
                }

                // 属性 Attributes
                HStack {
                    Text(LanguageManager.shared.localized("File Size"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.sizeString)
                         .font(.callout.monospacedDigit())
                }

                HStack {
                    Text(LanguageManager.shared.localized("Tracker"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.trackerHost)
                        .font(.callout.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                }

                HStack {
                    Text(LanguageManager.shared.localized("Server"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(serverName)
                        .font(.callout)
                }
            } header: {
                Text(LanguageManager.shared.localized("Data Brief"))
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(LanguageManager.shared.localized("Task Details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(task.id)-\(languageManager.selectedLanguage.rawValue)") {
            await loadTMDBData()
        }
    }

    private func loadTMDBData() async {
        guard tmdbPosterEnabled else { return }
        isLoadingTMDB = true
        if let details = await TMDBService.shared.fetchDetails(hash: task.id, name: task.name, context: modelContext) {
            self.tmdbItem = details
        }
        isLoadingTMDB = false
    }

    private func ratioColor(_ ratio: Double) -> Color {
        if ratio >= 1.0 { return .green }
        if ratio >= 0.5 { return .orange }
        return .red
    }
}
