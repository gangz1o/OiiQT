import SwiftUI
import SwiftData
import Observation
import UIKit

struct GlobalActivityEntry: Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: UUID
    let sourceName: String
    let title: String
    let link: String
    let pubDate: Date
    let fileSize: String?
    let targetServerId: UUID?
    let savePath: String
    let category: String
    let addPaused: Bool
    let priority: Int
}

private struct RSSSourceSnapshot: Sendable {
    let id: UUID
    let name: String
    let url: String
    let apiKey: String?
    let targetServerId: UUID?
    let savePath: String
    let category: String
    let addPaused: Bool
    let priority: Int
}

@MainActor
@Observable
final class AllActivityViewModel {
    var activities: [GlobalActivityEntry] = []
    var isLoading = false
    var sourceCount = 0

    func fetchGlobalActivities(context: ModelContext) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<RSSFeedSource>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        let persistedSources: [RSSFeedSource]
        do {
            persistedSources = try context.fetch(descriptor)
        } catch {
            sourceCount = 0
            activities = []
            return
        }

        let enabledSources = persistedSources.filter { $0.isEnabled }
        sourceCount = enabledSources.count
        guard !enabledSources.isEmpty else {
            activities = []
            return
        }

        let snapshots: [RSSSourceSnapshot] = enabledSources.map { source in
            RSSSourceSnapshot(
                id: source.id,
                name: source.name,
                url: source.url,
                apiKey: source.apiKey,
                targetServerId: source.targetServerId,
                savePath: source.savePath,
                category: source.category,
                addPaused: source.addPaused,
                priority: source.priority
            )
        }

        let merged = await withTaskGroup(of: [GlobalActivityEntry].self, returning: [GlobalActivityEntry].self) { group in
            for source in snapshots {
                group.addTask {
                    let transientSource = RSSFeedSource(
                        name: source.name,
                        url: source.url,
                        isEnabled: true,
                        lastUpdated: Date(),
                        autoDownload: false,
                        unreadCount: 0,
                        faviconUrl: nil,
                        apiKey: source.apiKey
                    )

                    do {
                        let items = try await RSSManager.shared.fetchRSS(source: transientSource)
                        return items.map { item in
                            GlobalActivityEntry(
                                id: "\(source.id.uuidString)|\(item.link)|\(item.pubDate.timeIntervalSince1970)",
                                sourceID: source.id,
                                sourceName: source.name,
                                title: item.title,
                                link: item.link,
                                pubDate: item.pubDate,
                                fileSize: item.fileSize,
                                targetServerId: source.targetServerId,
                                savePath: source.savePath,
                                category: source.category,
                                addPaused: source.addPaused,
                                priority: source.priority
                            )
                        }
                    } catch {
                        return []
                    }
                }
            }

            var result: [GlobalActivityEntry] = []
            for await activities in group {
                result.append(contentsOf: activities)
            }
            return result
        }

        activities = merged.sorted { $0.pubDate > $1.pubDate }
    }
}

struct AllActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appStateManager

    @State private var viewModel = AllActivityViewModel()
    @State private var pushingIDs: Set<String> = []
    @State private var syncNotice: SyncNotice?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.activities.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sourceCount == 0 || viewModel.activities.isEmpty {
                ContentUnavailableView(
                    LanguageManager.shared.localized("All Items"),
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text(LanguageManager.shared.localized("View the latest aggregated updates from all sources."))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.activities) { activity in
                            activityCard(activity)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await viewModel.fetchGlobalActivities(context: modelContext)
        }
        .refreshable {
            await viewModel.fetchGlobalActivities(context: modelContext)
        }
        .alert(item: $syncNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(localizedOKText))
            )
        }
    }

    @ViewBuilder
    private func activityCard(_ activity: GlobalActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(activity.sourceName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(sourceTint(for: activity.sourceID))
                    .clipShape(Capsule())

                Spacer()

                Text(relativeTime(activity.pubDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(activity.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(3)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                if let fileSize = activity.fileSize, !fileSize.isEmpty {
                    Text(fileSize)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                Button {
                    pushActivity(activity)
                } label: {
                    if pushingIDs.contains(activity.id) {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(pushingIDs.contains(activity.id))
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func pushActivity(_ activity: GlobalActivityEntry) {
        guard !pushingIDs.contains(activity.id) else { return }
        let link = activity.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else {
            syncNotice = SyncNotice(
                title: localizedTaskSyncFailedTitle,
                message: localizedEmptyLinkMessage
            )
            return
        }

        guard !appStateManager.servers.isEmpty else {
            syncNotice = SyncNotice(
                title: localizedTaskSyncFailedTitle,
                message: localizedNoServerMessage
            )
            return
        }

        pushingIDs.insert(activity.id)

        Task {
            defer {
                Task { @MainActor in
                    pushingIDs.remove(activity.id)
                }
            }

            let options = AddTorrentOptions(
                savePath: activity.savePath,
                category: activity.category,
                isPaused: activity.addPaused,
                isFirstLastPiecePriority: activity.priority > 0
            )

            do {
                try await appStateManager.addTorrents(
                    [link],
                    options: options,
                    to: activity.targetServerId
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    syncNotice = SyncNotice(
                        title: localizedTaskSyncedTitle,
                        message: localizedTaskSyncedMessage
                    )
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    syncNotice = SyncNotice(
                        title: localizedTaskSyncFailedTitle,
                        message: "\(localizedTaskSyncFailedMessagePrefix)\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = LanguageManager.shared.currentLocale
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sourceTint(for id: UUID) -> Color {
        let hash = abs(id.uuidString.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }

    private var localizedTaskSyncedTitle: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "Task Synced"
        }
        return "任务已同步"
    }

    private var localizedTaskSyncedMessage: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "Push request has been sent to server."
        }
        return "推送请求已发送到服务器。"
    }

    private var localizedTaskSyncFailedTitle: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "Task Sync Failed"
        }
        return "任务同步失败"
    }

    private var localizedTaskSyncFailedMessagePrefix: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "Unable to push task: "
        }
        return "无法推送任务："
    }

    private var localizedEmptyLinkMessage: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "This item does not contain a valid task link."
        }
        return "该条目未包含有效的任务链接。"
    }

    private var localizedNoServerMessage: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "No server is available. Please add a server in Settings first."
        }
        return "当前没有可用服务器，请先在设置中添加服务器。"
    }

    private var localizedOKText: String {
        if LanguageManager.shared.selectedLanguage == .english {
            return "OK"
        }
        return "确定"
    }
}

private struct SyncNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    AllActivityView()
        .modelContainer(for: [RSSFeedSource.self, RSSItem.self], inMemory: true)
        .environment(AppStateManager())
}
