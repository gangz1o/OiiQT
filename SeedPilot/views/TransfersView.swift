//
//  TransfersView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI


struct TransfersView: View {
    @Environment(AppStateManager.self) private var appStateManager

    @Environment(\.editMode) private var editMode
    @State private var searchText = ""
    @State private var selectedTaskHashes = Set<String>()

    // 状态筛选
    @State private var selectedStatus: String = "全部"
    let statusOptions = ["全部"] + TorrentStatus.allCases.map { $0.rawValue }

    // Batch Action States
    @State private var showingBatchLocationAlert = false
    @State private var newBatchLocation = ""
    @State private var showingBatchTrackerAlert = false
    @State private var newBatchTrackers = ""
    @State private var showingBatchDeleteConfirmation = false

    // 添加磁力链接
    @State private var showingAddMagnet = false
    @State private var magnetLink = ""

    // 筛选后的任务列表
    var filteredTasks: [TorrentTask] {
        let tasks = appStateManager.displayedTasks
        let statusFiltered = (selectedStatus == "全部") ? tasks : tasks.filter { $0.status.rawValue == selectedStatus }

        if searchText.isEmpty {
            return statusFiltered
        } else {
            return statusFiltered.filter { task in
                task.name.localizedCaseInsensitiveContains(searchText) ||
                task.trackerHost.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var navigationTitle: String {
        if editMode?.wrappedValue == .active {
            return selectedTaskHashes.isEmpty ? "请选择项目" : "已选中 \(selectedTaskHashes.count) 项"
        } else {
            return appStateManager.activeServerName ?? "传输任务"
        }
    }

    private var isEditing: Bool {
        editMode?.wrappedValue == .active
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
                        if !searchText.isEmpty {
                             ContentUnavailableView.search(text: searchText)
                        } else {
                            emptyState
                        }
                    } else {
                        List {
                            ForEach(filteredTasks) { task in
                                TorrentRowView(
                                    task: task,
                                    isSelected: selectedTaskHashes.contains(task.id),
                                    isEditing: isEditing,
                                    toggleSelection: {
                                        toggleSelection(for: task.id)
                                    },
                                    appStateManager: appStateManager
                                )
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .listRowSeparator(.hidden) // Hide default separator as cards have spacing
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !isEditing {
                                        Button(role: .destructive) {
                                            appStateManager.deleteTask(task, withData: true)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !isEditing {
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
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await appStateManager.refreshData()
                        }
                    }
                }

                // 2. 悬浮按钮 (FAB) - Only show when NOT editing
                if !isEditing {
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

                // 3. Batch Action Toolbar - Only show when editing
                if isEditing {
                    batchActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 10) // Lift slightly above bottom safe area
                }
            }
            // .sensoryFeedback removed here, triggered manually in Row
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索任务或 Tracker")
            .toolbar {
                // Leading: Server Menu OR Select All
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button {
                            if selectedTaskHashes.count == filteredTasks.count {
                                selectedTaskHashes.removeAll()
                            } else {
                                selectedTaskHashes = Set(filteredTasks.map { $0.id })
                            }
                        } label: {
                            Text(selectedTaskHashes.count == filteredTasks.count ? "取消全选" : "全选")
                        }
                    } else {
                        Menu {
                            Button {
                                withAnimation(.spring()) {
                                    appStateManager.activeServerId = nil
                                }
                            } label: {
                                Label("全部服务器", systemImage: "rectangle.stack.fill")
                            }

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
                        } label: {
                            Image(systemName: "server.rack")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // Trailing: Edit/Done + Filter
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                         if isEditing {
                            Button("完成") {
                                withAnimation {
                                    editMode?.wrappedValue = .inactive
                                    selectedTaskHashes.removeAll()
                                }
                            }
                            .bold()
                        } else {
                             Button {
                                withAnimation {
                                    editMode?.wrappedValue = .active
                                }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }

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
            .alert("批量修改保存路径", isPresented: $showingBatchLocationAlert) {
                TextField("新路径", text: $newBatchLocation)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    appStateManager.setTransferLocationBatch(Set(tasks), newLocation: newBatchLocation)
                    editMode?.wrappedValue = .inactive
                    selectedTaskHashes.removeAll()
                    newBatchLocation = ""
                }
            } message: {
                Text("请输入新的绝对路径。此操作将移动所选任务的数据。")
            }
            .alert("批量添加 Tracker", isPresented: $showingBatchTrackerAlert) {
                TextField("Tracker URL", text: $newBatchTrackers)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    appStateManager.editTrackersBatch(Set(tasks), newTrackers: newBatchTrackers)
                    editMode?.wrappedValue = .inactive
                    selectedTaskHashes.removeAll()
                    newBatchTrackers = ""
                }
            } message: {
                Text("请输入 Tracker URL。")
            }
            .confirmationDialog("批量删除", isPresented: $showingBatchDeleteConfirmation, titleVisibility: .visible) {
                 Button("删除任务 (保留数据)", role: .destructive) {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    for task in tasks {
                        appStateManager.deleteTask(task, withData: false)
                    }
                    editMode?.wrappedValue = .inactive
                    selectedTaskHashes.removeAll()
                }
                Button("删除任务和数据", role: .destructive) {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    // Use batch delete if available or loop
                     for task in tasks {
                        appStateManager.deleteTask(task, withData: true)
                    }
                    editMode?.wrappedValue = .inactive
                    selectedTaskHashes.removeAll()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("确定要删除选中的 \(selectedTaskHashes.count) 个任务吗？")
            }
        }
    }

    // MARK: - Helper Methods

    private func toggleSelection(for hash: String) {
        if selectedTaskHashes.contains(hash) {
            selectedTaskHashes.remove(hash)
        } else {
            selectedTaskHashes.insert(hash)
        }
    }

    private var batchActionBar: some View {
        HStack(spacing: 0) {
            Button {
                actionWithFeedback {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    appStateManager.resumeTasks(Set(tasks))
                }
            } label: {
                batchActionButton(icon: "play.fill", text: "开始")
            }
            .disabled(selectedTaskHashes.isEmpty)

            Divider().frame(height: 20)

            Button {
                actionWithFeedback {
                    let tasks = appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
                    appStateManager.pauseTasks(Set(tasks))
                }
            } label: {
                batchActionButton(icon: "pause.fill", text: "暂停")
            }
            .disabled(selectedTaskHashes.isEmpty)

            Divider().frame(height: 20)

            Button(role: .destructive) {
                if !selectedTaskHashes.isEmpty {
                     showingBatchDeleteConfirmation = true
                }
            } label: {
                batchActionButton(icon: "trash.fill", text: "删除", color: .red)
            }
            .disabled(selectedTaskHashes.isEmpty)
        }
        .frame(height: 60)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 30)
    }

    private func batchActionButton(icon: String, text: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.headline)
            Text(text)
                .font(.caption2.bold())
        }
        .foregroundStyle(color)
        .opacity(selectedTaskHashes.isEmpty ? 0.4 : 1.0) // Dim if disabled
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func actionWithFeedback(action: () -> Void) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        action()
        withAnimation {
            editMode?.wrappedValue = .inactive
            selectedTaskHashes.removeAll()
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
            Text(formatBytes(speed) + "/s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}





#Preview {
    TransfersView()
        .environment(AppStateManager())
}
