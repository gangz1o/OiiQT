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
    @State private var selectedStatus: TaskStatusFilter = .all
    // NEW: Sorting
    @State private var sortOption: SortOption = .dateAdded
    @State private var sortAscending: Bool = false // Default Descending (Newest first)
    // NEW: Tracker Filter
    @State private var selectedTracker: String = Self.allTrackersToken

    private static let allTrackersToken = "__ALL_TRACKERS__"

    // Batch Action States
    // ... (unchanged)

    // 添加任务
    @State private var showingAddMagnet = false

    // 筛选后的任务列表
    var filteredTasks: [TorrentTask] {
        var tasks = appStateManager.displayedTasks

        // 1. Status Filter
        if selectedStatus != .all {
            tasks = tasks.filter { selectedStatus.matches($0.status) }
        }

        // 2. Search Text
        if !searchText.isEmpty {
            tasks = tasks.filter { task in
                task.name.localizedCaseInsensitiveContains(searchText) ||
                task.trackerHost.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 3. Tracker Filter
        if selectedTracker != Self.allTrackersToken {
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
        return [Self.allTrackersToken] + unique.sorted()
    }

    private var navigationTitle: String {
        if editMode?.wrappedValue == .active {
            return selectedTaskHashes.isEmpty
                ? LanguageManager.shared.localized("Select Items")
                : String(
                    format: LanguageManager.shared.localized("Selected Items Count Format"),
                    locale: .current,
                    selectedTaskHashes.count
                )
        } else {
            return appStateManager.activeServerName ?? LanguageManager.shared.localized("Transfers")
        }
    }

    private var isEditing: Bool {
        editMode?.wrappedValue == .active
    }

    // Check if any filter is active for the badge
    private var isFilterActive: Bool {
        selectedStatus != .all || selectedTracker != Self.allTrackersToken || sortOption != .dateAdded || sortAscending != false
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
                            ContentUnavailableView(
                                LanguageManager.shared.localized("No Tasks"),
                                systemImage: "tray",
                                description: Text(LanguageManager.shared.localized("No tasks match the current filters"))
                            )
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
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !isEditing {
                                        Button(role: .destructive) {
                                            appStateManager.deleteTask(task, withData: true)
                                        } label: {
                                            Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !isEditing {
                                        if task.status == .paused {
                                            Button {
                                                appStateManager.resumeTask(task)
                                            } label: {
                                                Label(LanguageManager.shared.localized("Resume"), systemImage: "play.fill")
                                            }
                                            .tint(.green)
                                        } else {
                                            Button {
                                                appStateManager.pauseTask(task)
                                            } label: {
                                                Label(LanguageManager.shared.localized("Pause"), systemImage: "pause.fill")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                }
                                .background {
                                    if !isEditing {
                                        NavigationLink(destination: TorrentDetailView(task: task, appStateManager: appStateManager)) {
                                            EmptyView()
                                        }
                                        .opacity(0)
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: LanguageManager.shared.localized("Search Torrents or Trackers")
            )
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
                            Text(
                                selectedTaskHashes.count == filteredTasks.count
                                ? LanguageManager.shared.localized("Deselect All")
                                : LanguageManager.shared.localized("Select All")
                            )
                        }
                    } else {
                        Menu {
                            Button {
                                withAnimation(.spring()) {
                                    appStateManager.activeServerId = nil
                                }
                            } label: {
                                Label(LanguageManager.shared.localized("All Servers"), systemImage: "rectangle.stack.fill")
                            }

                            ForEach(appStateManager.servers) { server in
                                Button {
                                    withAnimation(.spring()) {
                                        appStateManager.activeServerId = server.id
                                    }
                                } label: {
                                    HStack {
                                        ServerBrandIcon(type: server.type, size: 20)
                                        Text(server.name)
                                        Spacer()
                                        if server.isOnline == true {
                                            Image(systemName: "circle.fill").foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "circle.fill").foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        } label: {
                            // Header Brand Indicator
                            ServerBrandIcon(type: appStateManager.activeServerType, size: 22)
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
                                Section(LanguageManager.shared.localized("Sort")) {
                                    Picker(LanguageManager.shared.localized("Sort By"), selection: $sortOption) {
                                        ForEach(SortOption.allCases) { option in
                                            Text(option.localizedDisplayName).tag(option)
                                        }
                                    }

                                    Toggle(isOn: $sortAscending) {
                                        Label(LanguageManager.shared.localized("Ascending"), systemImage: "arrow.up.arrow.down")
                                    }
                                }

                                // Section 2: Filter
                                Section(LanguageManager.shared.localized("Filter Tracker")) {
                                    Picker(LanguageManager.shared.localized("Tracker"), selection: $selectedTracker) {
                                        ForEach(uniqueTrackers, id: \.self) { tracker in
                                            Text(
                                                tracker == Self.allTrackersToken
                                                ? LanguageManager.shared.localized("All Trackers")
                                                : tracker
                                            )
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .tag(tracker)
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
                            Button(LanguageManager.shared.localized("Done")) {
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
            Text(LanguageManager.shared.localized("No Tasks"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
            // Left: Assets Snapshot (Seeds + Size)
            HStack(spacing: 12) {
                // Seeding Count
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(appStateManager.displayedSeedingCount)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Total Size
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(appStateManager.displayedSeedingSize))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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

// MARK: - Brand Icon Component
struct ServerBrandIcon: View {
    let type: ServerType?
    let size: CGFloat

    var body: some View {
        Group {
            if let type = type {
                if type == .transmission {
                    if UIImage(named: "tr_logo") != nil {
                        Image("tr_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.orange)
                    }
                } else {
                    if UIImage(named: "qb_logo") != nil {
                        Image("qb_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "network")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                // All Servers (Grid Icon)
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}





#Preview {
    TransfersView()
        .environment(AppStateManager())
}
