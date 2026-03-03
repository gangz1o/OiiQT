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

    private var serverType: ServerType? {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.type
    }

    private var displayCategory: String? {
        guard let serverType, serverType != .transmission else { return nil }
        let trimmed = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedTags: [String] {
        Array(
            Set(
                task.tags
                    .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasTaxonomyMetadata: Bool {
        displayCategory != nil || !normalizedTags.isEmpty
    }

    private var taskErrorDetail: String? {
        let normalizedMessage = task.errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptyMessage = (normalizedMessage?.isEmpty == false) ? normalizedMessage : nil

        switch serverType {
        case .transmission:
            if let nonEmptyMessage { return nonEmptyMessage }

            switch task.errorCode ?? 0 {
            case 1:
                return LanguageManager.shared.localized("Transmission tracker warning")
            case 2:
                return LanguageManager.shared.localized("Transmission tracker error")
            case 3:
                return LanguageManager.shared.localized("Transmission local error")
            case let code where code != 0:
                return String(
                    format: LanguageManager.shared.localized("Transmission reported error code: %d"),
                    code
                )
            default:
                return task.status == .error
                    ? LanguageManager.shared.localized("Transmission reported an error")
                    : nil
            }

        case .qBittorrent:
            guard task.status == .error else { return nil }
            let stateToken = nonEmptyMessage?.lowercased() ?? ""

            switch stateToken {
            case "missingfiles":
                return LanguageManager.shared.localized("Torrent data files are missing. Verify storage mount points or use Set Location.")
            case "unregistered", "unregisteredtorrent":
                return LanguageManager.shared.localized("Torrent is unregistered on tracker.")
            case "error":
                return LanguageManager.shared.localized("qBittorrent reported a torrent error")
            case "unknown":
                return LanguageManager.shared.localized("qBittorrent reported an unknown torrent state")
            case "":
                return LanguageManager.shared.localized("qBittorrent reported a torrent error")
            default:
                return String(
                    format: LanguageManager.shared.localized("qBittorrent reported state: %@"),
                    stateToken
                )
            }

        case nil:
            return nonEmptyMessage
        }
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
                if hasTaxonomyMetadata {
                    HStack(alignment: .top) {
                        Text("\(LanguageManager.shared.localized("Category")) / \(LanguageManager.shared.localized("Tags"))")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 12)

                        FlowLayout(spacing: 8, rowAlignment: .trailing) {
                            if let category = displayCategory {
                                ColoredTagPill(
                                    text: category,
                                    font: .caption.weight(.semibold),
                                    horizontalPadding: 10,
                                    verticalPadding: 5,
                                    color: TagColorManager.color(for: "category:\(category)")
                                )
                                .fixedSize(horizontal: true, vertical: false)
                            }

                            ForEach(normalizedTags, id: \.self) { tag in
                                ColoredTagPill(
                                    text: tag,
                                    font: .caption.weight(.semibold),
                                    horizontalPadding: 10,
                                    verticalPadding: 5
                                )
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

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

                if let taskErrorDetail {
                    HStack(alignment: .top) {
                        Text(LanguageManager.shared.localized("Error Details"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(taskErrorDetail)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                    }
                }

                NavigationLink {
                    TorrentTrackerDetailListView(task: task, appStateManager: appStateManager)
                } label: {
                    HStack {
                        Text(LanguageManager.shared.localized("Tracker"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(task.trackerHost)
                            .font(.callout.monospacedDigit())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.primary)
                    }
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
        if let details = await TMDBService.shared.fetchDetails(hash: task.hash, name: task.name, context: modelContext) {
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

private struct TorrentTrackerDetailListView: View {
    let task: TorrentTask
    var appStateManager: AppStateManager

    @State private var trackers: [TorrentTrackerInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && trackers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let errorMessage, trackers.isEmpty {
                Section {
                    ContentUnavailableView(
                        LanguageManager.shared.localized("Failed to load tracker details"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
                .listRowBackground(Color.clear)
            } else if trackers.isEmpty {
                Section {
                    ContentUnavailableView(
                        LanguageManager.shared.localized("No Tracker Data"),
                        systemImage: "link",
                        description: Text(LanguageManager.shared.localized("No tracker status available"))
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(trackers) { tracker in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                if let tier = tracker.tier {
                                    Text("L\(tier)")
                                        .font(.caption2.monospacedDigit().bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                                }

                                Text(tracker.url)
                                    .font(.callout.monospacedDigit())
                                    .lineLimit(2)
                                    .truncationMode(.middle)

                                Spacer(minLength: 8)

                                Text(tracker.status.localizedText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(tracker.status.color)
                                    .fixedSize()
                            }

                            HStack(spacing: 14) {
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Peers"),
                                    value: tracker.peers
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Seeds"),
                                    value: tracker.seeds
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Leeches"),
                                    value: tracker.leeches
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Downloads"),
                                    value: tracker.downloaded
                                )
                            }

                            if let message = tracker.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(tracker.status == .failed ? .red : .secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Tracker"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LanguageManager.shared.localized("Tracker"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadTrackers(showLoadingIndicator: false)
        }
        .task(id: task.id) {
            await loadTrackers(showLoadingIndicator: true)
        }
    }

    private func loadTrackers(showLoadingIndicator: Bool) async {
        if showLoadingIndicator || trackers.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let fetched = try await appStateManager.fetchTrackers(for: task)
            errorMessage = nil
            if fetched != trackers {
                trackers = fetched
            }
        } catch {
            if trackers.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct TrackerMetricPair: View {
    let title: String
    let value: Int?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "--")
                .foregroundStyle(.primary)
        }
        .font(.caption.monospacedDigit())
    }
}
