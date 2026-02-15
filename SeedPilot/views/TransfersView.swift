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
    // NEW: Sorting
    @State private var sortOption: SortOption = .dateAdded
    @State private var sortAscending: Bool = false // Default Descending (Newest first)
    // NEW: Tracker Filter
    @State private var selectedTracker: String = "全部 Tracker"

    // Batch Action States
    // ... (unchanged)

    // 添加任务
    @State private var showingAddMagnet = false

    // 筛选后的任务列表
    var filteredTasks: [TorrentTask] {
        var tasks = appStateManager.displayedTasks

        // 1. Status Filter
        if selectedStatus != "全部" {
            tasks = tasks.filter { $0.status.rawValue == selectedStatus }
        }

        // 2. Search Text
        if !searchText.isEmpty {
            tasks = tasks.filter { task in
                task.name.localizedCaseInsensitiveContains(searchText) ||
                task.trackerHost.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 3. Tracker Filter
        if selectedTracker != "全部 Tracker" {
            tasks = tasks.filter { $0.trackerHost == selectedTracker }
        }

        // 4. Sort
        return tasks.sorted { t1, t2 in
            var result: Bool
            switch sortOption {
            case .dateAdded:
                result = t1.addedTime < t2.addedTime
            case .name:
                result = t1.name.localizedStandardCompare(t2.name) == .orderedAscending
            case .downloadSpeed:
                result = t1.downloadSpeed < t2.downloadSpeed
            case .uploadSpeed:
                result = t1.uploadSpeed < t2.uploadSpeed
            case .size:
                result = t1.size < t2.size
            case .progress:
                 result = t1.progress < t2.progress
            }
            return sortAscending ? result : !result
        }
    }

    // Helper to extract unique trackers
    var uniqueTrackers: [String] {
        let hosts = appStateManager.allTasks.map { $0.trackerHost }
        let unique = Set(hosts)
        return ["全部 Tracker"] + unique.sorted()
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

    // Check if any filter is active for the badge
    private var isFilterActive: Bool {
        selectedStatus != "全部" || selectedTracker != "全部 Tracker" || sortOption != .dateAdded || sortAscending != false
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // 0. 服务器状态栏 (Pinned Top)
                    ServerStatusBar(appStateManager: appStateManager)
                        .background(Color(uiColor: .systemBackground))

                    // 0.5. Quick Filter Bar (Capsule) - Hide when editing
                    if !isEditing {
                        QuickFilterBar(selectedStatus: $selectedStatus)
                            .padding(.bottom, 8) // Spacing from list
                            .background(Color(uiColor: .systemBackground))
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(Color(uiColor: .separator)),
                                alignment: .bottom
                            )
                    }

                    // 1. 任务列表
                    if filteredTasks.isEmpty {
                        if !searchText.isEmpty {
                             ContentUnavailableView.search(text: searchText)
                        } else {
                            ContentUnavailableView("无任务", systemImage: "tray", description: Text("当前筛选条件下没有任务"))
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
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)) // Wider spacing
                                .listRowSeparator(.hidden)
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
                        .animation(.spring(), value: filteredTasks) // Animate reordering
                    }
                }

                // 3. Batch Action Panel - Only show when editing
                if isEditing && !selectedTaskHashes.isEmpty {
                     BatchActionPanel(
                        selectedTaskHashes: $selectedTaskHashes,
                        isEditing: Binding(
                            get: { editMode?.wrappedValue == .active },
                            set: { if !$0 { editMode?.wrappedValue = .inactive } }
                        )
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 0)
                    .zIndex(2)
                }

                // FAB (Floating Action Button) for Adding Task
                if !isEditing {
                    Button {
                        showingAddMagnet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
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

                // Trailing: Add + Filter + Edit/Done
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Unified Sort & Filter Menu
                         if !isEditing {
                            Menu {
                                // Section 1: Sort
                                Section("排序") {
                                    Picker("排序方式", selection: $sortOption) {
                                        ForEach(SortOption.allCases) { option in
                                            Text(option.rawValue).tag(option)
                                        }
                                    }

                                    Toggle(isOn: $sortAscending) {
                                        Label("升序排列", systemImage: "arrow.up.arrow.down")
                                    }
                                }

                                // Section 2: Filter
                                Section("筛选 Tracker") {
                                    Picker("Tracker", selection: $selectedTracker) {
                                        ForEach(uniqueTrackers, id: \.self) { tracker in
                                            Text(tracker).tag(tracker)
                                        }
                                    }
                                }

                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.system(size: 17, weight: .semibold))

                                    if isFilterActive {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 2, y: -2)
                                    }
                                }
                            }
                        }

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
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .sheet(isPresented: $showingAddMagnet) {
                AddTorrentView()
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
