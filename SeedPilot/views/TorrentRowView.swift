//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI

struct TorrentRowView: View {
    let task: TorrentTask
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @Environment(\.modelContext) private var modelContext
    var appStateManager: AppStateManager

    @State private var posterURL: URL?
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingLocationAlert = false
    @State private var newLocation = ""
    @State private var showingTrackersAlert = false
    @State private var newTrackers = ""
    @State private var showingDeleteConfirmation = false
    @State private var isLoadingPoster = false
    @State private var showingManualMatchSheet = false
    // Removed newManualMatchName and showingManualMatchAlert as they are moved to ManualMatchView

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // MARK: - 1. Left Poster Area
            if showTMDBData {
                posterArea
            }

            // MARK: - 2. Right Content Area
            VStack(alignment: .leading, spacing: 8) {
                // Row 1: Title + Speed
                HStack(alignment: .top) {
                    Text(task.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        // Removed layoutPriority(1) to prevent squashing speed capsule

                    Spacer()

                    speedCapsule
                        .layoutPriority(1) // Ensure speed capsule is fully visible
                }

                // Row 2: Status + Stats
                HStack(spacing: 12) {
                    // Status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(task.status.rawValue)
                    }
                    .foregroundStyle(statusColor)

                    // Downloaded
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                        Text(task.downloadedString)
                    }

                    // Uploaded
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                        Text(task.uploadedString)
                    }

                    // Percentage
                    HStack(spacing: 2) {
                        Image(systemName: "percent")
                            .font(.caption2)
                        Text(task.percentString)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                // Row 3: Tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TagCapsule(text: task.trackerHost, icon: "network")
                        TagCapsule(text: task.savePathShort, icon: "folder")
                        if !task.tags.isEmpty {
                            ForEach(task.tags.split(separator: ","), id: \.self) { tag in
                                TagCapsule(text: String(tag), icon: "tag")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if task.status == .paused {
                Button {
                    appStateManager.resumeTask(task)
                } label: {
                    Label("恢复", systemImage: "play.fill")
                }
            } else {
                Button {
                    appStateManager.pauseTask(task)
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
            }

            Divider()

            Button {
                newName = task.name
                showingRenameAlert = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Menu {
                // Advanced Tools Submenu
                Menu {
                    Button {
                        appStateManager.recheckTask(task)
                    } label: {
                        Label("强制重新校验", systemImage: "checkmark.seal")
                    }

                    Button {
                        appStateManager.reannounceTask(task)
                    } label: {
                        Label("强制重新汇报", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label("高级工具", systemImage: "gearshape.2")
                }

                // Download Settings Submenu
                Menu {
                    Button {
                        appStateManager.toggleSequentialDownload(task)
                    } label: {
                        let icon = (task.isSequential == true) ? "checkmark" : "text.insert.secondary"
                        Label("顺序下载", systemImage: icon)
                    }

                    Button {
                        appStateManager.toggleFirstLastPiecePriority(task)
                    } label: {
                        let icon = (task.isFirstLastPiecePriority == true) ? "checkmark" : "arrow.up.arrow.down.square"
                        Label("首/尾优先", systemImage: icon)
                    }
                } label: {
                    Label("下载设置", systemImage: "slider.horizontal.3")
                }
            } label: {
                Label("更多操作", systemImage: "ellipsis.circle")
            }

            Divider()

            Button {
                appStateManager.forceStartTask(task)
            } label: {
                Label("强制开始", systemImage: "bolt.fill")
            }

            Button {
                newLocation = task.savePath
                showingLocationAlert = true
            } label: {
                Label("设置保存路径", systemImage: "folder.badge.gear")
            }

            Button {
                newTrackers = task.tracker
                showingTrackersAlert = true
            } label: {
                Label("编辑 Tracker", systemImage: "network.badge.shield.half.filled")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }

            Divider()

            if showTMDBData {
                Button {
                    showingManualMatchSheet = true
                } label: {
                    Label("手动匹配海报", systemImage: "photo.badge.plus")
                }
            }
        }
        .alert("重命名任务", isPresented: $showingRenameAlert) {
            TextField("新名称", text: $newName)
            Button("取消", role: .cancel) { }
            Button("确定") {
                appStateManager.renameTask(task, newName: newName)
            }
        } message: {
            Text("请输入新的任务名称。")
        }
        .alert("设置保存路径", isPresented: $showingLocationAlert) {
            TextField("路径", text: $newLocation)
            Button("取消", role: .cancel) { }
            Button("确定") {
                appStateManager.setLocation(task, newLocation: newLocation)
            }
        } message: {
            Text("请输入新的绝对路径 (例如 /downloads/movie)。")
        }
        .alert("编辑 Tracker", isPresented: $showingTrackersAlert) {
            TextField("Tracker URL", text: $newTrackers)
            Button("取消", role: .cancel) { }
            Button("确定") {
                appStateManager.editTrackers(task, newTrackers: newTrackers)
            }
        } message: {
            Text("请输入 Tracker URL。多个 URL 请尝试用逗号分隔（取决于服务器支持）。")
        }
        .sheet(isPresented: $showingManualMatchSheet) {
            ManualMatchView(taskName: task.name, taskHash: task.id)
                .presentationDetents([.medium, .large])
                .onDisappear {
                    // Refresh poster on disappear if changed
                    // But how do we know if changed?
                    // We can force re-fetch or observe
                    // Let's force re-fetch by toggling a state or calling load
                    // Trigger refresh
                    refreshPoster()
                }
        }
        .confirmationDialog("确认删除", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除任务 (保留数据)", role: .destructive) {
                appStateManager.deleteTask(task, withData: false)
            }
            Button("删除任务和数据", role: .destructive) {
                appStateManager.deleteTask(task, withData: true)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("您确定要删除 \"\(task.name)\" 吗？")
        }
        .task(id: task.name) {
             refreshPoster()
        }
    }

    private func refreshPoster() {
        if showTMDBData {
            isLoadingPoster = true
            Task {
                // Pass modelContext for SwiftData persistence
                let url = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext)
                await MainActor.run {
                    self.posterURL = url
                    self.isLoadingPoster = false
                }
            }
        }
    }

    // MARK: - Components

    private var posterArea: some View {
        Group {
            if let url = posterURL {
                CachedAsyncImage(url: url, cacheKey: task.id + ".jpg") { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } placeholder: {
                     placeholder
                }
            } else {
                if isLoadingPoster {
                     placeholder
                } else {
                     failureView
                }
            }
        }
        .frame(width: 65, height: 97.5) // 1.5:1 ratio
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                ProgressView()
            }
    }

    private var failureView: some View {
        Color.gray.opacity(0.1)
            .overlay {
                Image(systemName: "sparkles.tv")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
    }

    private var speedCapsule: some View {
        HStack(spacing: 4) {
            if task.status == .downloading {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(torrentByteFormatter.string(fromByteCount: task.downloadSpeed) + "/s")
            } else if task.status == .seeding {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(torrentByteFormatter.string(fromByteCount: task.uploadSpeed) + "/s")
            } else {
                Text(task.status.rawValue)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .seeding: return .green
        case .error: return .red
        default: return .secondary
        }
    }
}

// Helper View for Tags
struct TagCapsule: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
}


