//
//  DashboardRecentFinishedModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

struct DashboardRecentFinishedModuleView: View {
    let tasks: [TorrentTask]
    @State private var isExpanded = false

    private let collapsedLimit = 3

    static func hasRecentFinishedTasks(in tasks: [TorrentTask]) -> Bool {
        tasks.contains { $0.status == .completed || $0.completionDate != nil || $0.progress >= 1 }
    }

    private var recentFinishedTasks: [TorrentTask] {
        tasks
            .filter { $0.status == .completed || $0.completionDate != nil || $0.progress >= 1 }
            .sorted {
                let lhsDate = $0.completionDate ?? $0.addedTime
                let rhsDate = $1.completionDate ?? $1.addedTime
                return lhsDate > rhsDate
            }
            .prefix(10)
            .map { $0 }
    }

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

    var body: some View {
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
            .onChange(of: recentFinishedTasks.count) { _, newCount in
                if newCount <= collapsedLimit, isExpanded {
                    isExpanded = false
                }
            }
        }
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
