//
//  TransfersView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

struct TransfersView: View {
    @Environment(AppStateManager.self) private var appStateManager

    // 状态筛选
    @State private var selectedStatus: String = "全部"
    let statusOptions = ["全部"] + TorrentStatus.allCases.map { $0.rawValue }

    // 添加磁力链接
    @State private var showingAddMagnet = false
    @State private var magnetLink = ""

    // 筛选后的任务列表
    var filteredTasks: [TorrentTask] {
        let tasks = appStateManager.displayedTasks
        if selectedStatus == "全部" {
            return tasks
        } else {
            return tasks.filter { $0.status.rawValue == selectedStatus }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // 0. 服务器状态栏 (Pinned Top)
                    ServerStatusBar(appStateManager: appStateManager)
                        .background(Color(uiColor: .systemBackground)) // Match Nav Bar
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .bottom
                        )

                    // 1. 任务列表
                    if filteredTasks.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(filteredTasks) { task in
                                TorrentRowView(task: task, appStateManager: appStateManager)
                                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) // Custom insets for alignment
                                    .listRowSeparator(.visible) // Or hidden if we use our own dividers
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            appStateManager.deleteTask(task, withData: true) // Default to quick delete with data? Or allow logic?
                                            // Swipe usage usually implies quick delete.
                                            // Step 543 added deleteTask(task, withData: Bool)
                                            // Old code used deleteTasks([task]) which was bulk delete.
                                            // Let's use deleteTasks([task]) for now or appStateManager.deleteTask(task, withData: true)
                                            // Let's stick to simple delete for swipe.
                                            appStateManager.deleteTask(task, withData: true)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if task.status == .paused {
                                            Button {
                                                appStateManager.resumeTask(task)
                                            } label: {
                                                Label("恢复", systemImage: "play.fill")
                                            }
                                            .tint(.green)
                                        } else {
                                            Button {
                                                appStateManager.pauseTask(task)
                                            } label: {
                                                Label("暂停", systemImage: "pause.fill")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }

                // 2. 悬浮按钮 (FAB)
                Button {
                    showingAddMagnet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
                }
                .padding()
            }
            .navigationTitle(appStateManager.activeServerName ?? "传输任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                // 全部服务器
                Button {
                    withAnimation(.spring()) {
                        appStateManager.activeServerId = nil
                    }
                } label: {
                    Label("全部服务器", systemImage: "rectangle.stack.fill")
                }

                // Server List
                ForEach(appStateManager.servers) { server in
                    Button {
                        withAnimation(.spring()) {
                            appStateManager.activeServerId = server.id
                        }
                    } label: {
                        HStack {
                            Text(server.name)
                            if server.isOnline == true {
                                Image(systemName: "circle.fill").foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("筛选状态", selection: $selectedStatus) {
                            ForEach(statusOptions, id: \.self) { status in
                                Text(status)
                                    .tag(status)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .alert("添加磁力链接", isPresented: $showingAddMagnet) {
                TextField("粘贴磁力链接", text: $magnetLink)
                Button("取消", role: .cancel) { }
                Button("添加") {
                    appStateManager.addMagnetLink(magnetLink)
                    magnetLink = ""
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无任务")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Status Bar Component

struct ServerStatusBar: View {
    var appStateManager: AppStateManager

    var body: some View {
        HStack {
            // Left: Server Type / Icon
            HStack(spacing: 6) {
                if let type = appStateManager.activeServerType {
                    Image(systemName: type == .qBittorrent ? "network" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.primary)
                }

                Text(appStateManager.activeServerName ?? "All Servers")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: Speeds
            HStack(spacing: 12) {
                SpeedLabel(icon: "arrow.down", speed: appStateManager.displayedDownloadSpeed, color: .green)
                SpeedLabel(icon: "arrow.up", speed: appStateManager.displayedUploadSpeed, color: .blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct SpeedLabel: View {
    let icon: String
    let speed: Int64
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(ByteCountFormatter.string(fromByteCount: speed, countStyle: .binary) + "/s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}





#Preview {
    TransfersView()
        .environment(AppStateManager())
}
