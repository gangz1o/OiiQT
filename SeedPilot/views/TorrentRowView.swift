//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI

struct TorrentRowView: View {
    let task: TorrentTask
    let isSelected: Bool
    let isEditing: Bool
    let toggleSelection: () -> Void

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

    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Checkbox (Edit Mode Only)
            if isEditing {
                Button {
                    toggleSelection()
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                        .contentShape(Rectangle()) // Make touch area larger
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .padding(.leading, 8)
            }

            // MARK: - Content
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // MARK: - 1. Left Poster Area
                    if showTMDBData {
                        posterArea
                    }

                    // MARK: - 2. Right Content Area
                    VStack(alignment: .leading, spacing: 8) {
                        // Feature 1: Top Status Bar
                        HStack {
                            // Tracker
                            Text(task.trackerHost)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())

                            // Seeding Time / Added Date if not seeding
                            if task.status == .seeding {
                                 HStack(spacing: 2) {
                                    Image(systemName: "clock")
                                    Text(task.seedingTimeString)
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Status & Percent
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(task.status.rawValue)
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor)
                                Text(task.percentString)
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(statusColor)
                            }
                        }

                        // Title
                        Text(task.name)
                            .font(.system(size: 14, weight: .medium)) // Slightly refined font size
                            .foregroundStyle(.primary)
                            .lineLimit(2) // Allow 2 lines for full names
                            .fixedSize(horizontal: false, vertical: true)

                        // Feature 3: Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5))
                                Capsule().fill(statusColor)
                                    .frame(width: max(0, geo.size.width * CGFloat(task.progress)))
                                    .animation(.smooth, value: task.progress)
                            }
                        }
                        .frame(height: 4) // Slimmer

                        // Feature 2: 3x2 Data Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], spacing: 6) {
                            // Row 1
                            GridRowIconText(icon: "arrow.down.circle", text: formatBytes(task.downloadSpeed) + "/s", color: .secondary)
                            GridRowIconText(icon: "arrow.down", text: "\(task.numPeers)/\(task.totalPeers)", color: .secondary) // Peers
                            GridRowIconText(icon: "doc", text: task.sizeString, color: .secondary) // Size

                            // Row 2
                            GridRowIconText(icon: "arrow.up.circle", text: formatBytes(task.uploadSpeed) + "/s", color: .secondary)
                            GridRowIconText(icon: "leaf", text: "\(task.numSeeds)/\(task.totalSeeds)", color: .secondary) // Seeds
                            GridRowIconText(icon: "arrow.left.and.right", text: String(format: "%.2f", task.ratio), color: .secondary) // Ratio
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground)) // Card background
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2) // Subtle shadow
        }
        .contentShape(Rectangle()) // Make the whole row tappable
        .onTapGesture {
            if isEditing {
                toggleSelection()
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
        }
        .contextMenu {
            if !isEditing {
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
                CachedAsyncImage(url: url) { image in
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
                Text(formatBytes(task.downloadSpeed) + "/s")
            } else if task.status == .seeding {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(formatBytes(task.uploadSpeed) + "/s")
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
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
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

struct GridRowIconText: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}


