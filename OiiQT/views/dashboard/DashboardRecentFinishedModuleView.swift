//
//  DashboardRecentFinishedModuleView.swift
//  OiiQT
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

struct DashboardRecentFinishedModuleView: View {
    let tasks: [TorrentTask]
    let refreshKey: String

    @State private var isExpanded = false
    @State private var recentFinishedTasks: [TorrentTask] = []

    private let collapsedLimit = 3

    private var displayedTasks: [TorrentTask] {
        if isExpanded {
            return recentFinishedTasks
        }
        return Array(recentFinishedTasks.prefix(collapsedLimit))
    }

    private var canToggleExpand: Bool {
        recentFinishedTasks.count > collapsedLimit
    }

    private var toggleButtonTitle: String {
        isExpanded
            ? LanguageManager.shared.localized("Collapse")
            : LanguageManager.shared.localized("View All")
    }

    init(tasks: [TorrentTask], refreshKey: String) {
        self.tasks = tasks
        self.refreshKey = refreshKey
        _recentFinishedTasks = State(initialValue: Self.computeRecentFinishedTasks(from: tasks))
    }

    var body: some View {
        Group {
            if !recentFinishedTasks.isEmpty {
                // 性能优化：使用 LazyVStack 懒加载，仅实例化可见行
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedTasks.enumerated()), id: \.element.id) { index, task in
                        DashboardRecentFinishedListRow(task: task)

                        if index < displayedTasks.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }

                    if canToggleExpand {
                        Divider()
                            .padding(.leading, 14)

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(toggleButtonTitle)
                                    .font(.footnote.weight(.semibold))

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: refreshKey) {
            let latest = await Task.detached(priority: .utility) {
                DashboardRecentFinishedModuleView.computeRecentFinishedTasks(from: tasks)
            }.value
            guard !Task.isCancelled else { return }
            recentFinishedTasks = latest
            if latest.count <= collapsedLimit, isExpanded {
                isExpanded = false
            }
        }
    }

    nonisolated private static func computeRecentFinishedTasks(from tasks: [TorrentTask]) -> [TorrentTask] {
        var finishedTasks: [TorrentTask] = []
        finishedTasks.reserveCapacity(min(max(tasks.count / 8, 8), 256))

        for task in tasks {
            if task.status == .completed || task.status == .seeding || task.completionDate != nil || task.progress >= 0.999 {
                finishedTasks.append(task)
            }
        }

        finishedTasks.sort {
            let lhsDate = $0.completionDate ?? $0.addedTime
            let rhsDate = $1.completionDate ?? $1.addedTime
            return lhsDate > rhsDate
        }

        if finishedTasks.count > 10 {
            finishedTasks.removeSubrange(10..<finishedTasks.count)
        }
        return finishedTasks
    }
}

private struct DashboardRecentFinishedListRow: View {
    let task: TorrentTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.recentListIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(task.recentListIconColor)
                .frame(width: 20)

            Text(task.name)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(task.sizeString)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private extension TorrentTask {
    var recentListIconName: String {
        let ext = (name as NSString).pathExtension.lowercased()

        if ["mkv", "mp4", "mov", "avi", "wmv", "m4v", "ts", "rmvb", "flv"].contains(ext) {
            return "film"
        }
        if ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) {
            return "doc.zipper"
        }
        if ["iso", "img", "dmg"].contains(ext) {
            return "externaldrive"
        }
        if ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md"].contains(ext) {
            return "doc.text"
        }
        if ["app", "pkg", "exe", "msi"].contains(ext) {
            return "shippingbox"
        }
        return "doc"
    }

    var recentListIconColor: Color {
        let ext = (name as NSString).pathExtension.lowercased()

        if ["mkv", "mp4", "mov", "avi", "wmv", "m4v", "ts", "rmvb", "flv"].contains(ext) {
            return .purple
        }
        if ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) {
            return .orange
        }
        if ["iso", "img", "dmg"].contains(ext) {
            return .teal
        }
        return .secondary
    }
}
