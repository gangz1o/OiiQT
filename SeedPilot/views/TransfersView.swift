//
//  TransfersView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI


struct TransfersView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @ObservedObject private var storeManager = StoreManager.shared
    @AppStorage("enableGlobalTaskAggregation") private var enableGlobalTaskAggregation: Bool = false
    @AppStorage("recentSearches") private var recentSearchesData: Data = Data()

    @Environment(\.editMode) private var editMode
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedTaskHashes = Set<String>()
    @State private var hasAttemptedInitialLoad = false
    @State private var filteredTasks: [TorrentTask] = []
    @State private var uniqueTrackersCache: [String] = [Self.allTrackersToken]
    @State private var isFilteringTasks = false
    @State private var shouldHintOverlayLoadingForCurrentFilterPass = false
    @State private var isOverlayLoadingVisible = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var filterComputationTask: Task<Void, Never>?
    @State private var trackerListComputationTask: Task<Void, Never>?
    @State private var overlayLoadingDelayTask: Task<Void, Never>?

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
    @State private var selectedTorrentForAction: TorrentTask?
    @State private var selectedTorrentPosterURL: URL?

    // Helper to extract unique trackers
    var uniqueTrackers: [String] {
        guard isTransfersTabActive else { return [Self.allTrackersToken] }
        return uniqueTrackersCache
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

    private var canUseGlobalTaskAggregation: Bool {
        storeManager.isProUser && enableGlobalTaskAggregation
    }

    private var isTransfersTabActive: Bool {
        appStateManager.selectedTab == .transfers
    }

    private var shouldShowTasksLoadingState: Bool {
        guard isTransfersTabActive else { return false }
        guard filteredTasks.isEmpty else { return false }
        if !appStateManager.hasInitialDataLoaded && !appStateManager.servers.isEmpty {
            return true
        }
        return appStateManager.isRefreshingTasks || isFilteringTasks
    }

    private var shouldRequestOverlayTasksLoadingState: Bool {
        guard isTransfersTabActive else { return false }
        guard !filteredTasks.isEmpty else { return false }
        guard shouldHintOverlayLoadingForCurrentFilterPass else { return false }
        return isFilteringTasks
    }

    var body: some View {
        transfersPresentedView
    }

    private var transfersPresentedView: some View {
        transfersLifecycleBoundView
            .sheet(isPresented: $showingAddMagnet) {
                AddTorrentView()
            }
            .sheet(item: $selectedTorrentForAction) { selectedTask in
                TorrentActionSheetView(
                    task: selectedTask,
                    posterURL: selectedTorrentPosterURL,
                    appStateManager: appStateManager,
                    onPosterChanged: {
                        TMDBService.shared.clearCache(for: selectedTask.hash)
                        NotificationCenter.default.post(
                            name: .tmdbPosterDidChange,
                            object: nil,
                            userInfo: ["hash": selectedTask.hash]
                        )
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    private var transfersLifecycleBoundView: some View {
        transfersLifecycleBoundViewPart1
            .onChange(of: selectedStatus) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: sortOption) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: sortAscending) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: selectedTracker) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearchDebounce()
            }
            .onChange(of: debouncedSearchText) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: isFilteringTasks) { _, _ in
                syncOverlayLoadingVisibility()
            }
            .onChange(of: filteredTasks.count) { _, _ in
                syncOverlayLoadingVisibility()
            }
            .onDisappear {
                handleTransfersViewDisappear()
            }
    }

    private var transfersLifecycleBoundViewPart1: some View {
        transfersNavigationBase
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                handleTransfersViewAppear()
            }
            .onChange(of: enableGlobalTaskAggregation) { _, _ in
                applyGlobalAggregationSafetyFallbackIfNeeded()
            }
            .onChange(of: storeManager.isProUser) { _, _ in
                applyGlobalAggregationSafetyFallbackIfNeeded()
            }
            .onChange(of: appStateManager.servers.count) { _, _ in
                applyGlobalAggregationSafetyFallbackIfNeeded()
            }
            .onChange(of: appStateManager.tasksRevision) { _, _ in
                scheduleFilteredTasksRecompute()
                scheduleUniqueTrackersRecompute()
            }
            .onChange(of: appStateManager.activeServerId) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: appStateManager.selectedTab) { _, newValue in
                handleSelectedTabChanged(newValue)
            }
    }

    private var transfersNavigationBase: some View {
        AnyView(
            NavigationStack {
                transfersRootContent
                    .navigationTitle(navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: LanguageManager.shared.localized("Search Torrents or Trackers")
                    )
                    .searchSuggestions {
                        if searchText.isEmpty {
                            ForEach(recentSearches, id: \.self) { term in
                                Label(term, systemImage: "clock.arrow.circlepath")
                                    .searchCompletion(term)
                            }
                        }
                    }
                    .onSubmit(of: .search) {
                        saveSearchTerm(searchText)
                    }
                    .toolbar { transfersToolbarContent }
            }
        )
    }

    // MARK: - Search History

    private var recentSearches: [String] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: recentSearchesData) else {
            return []
        }
        return decoded
    }

    private func saveSearchTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = recentSearches.filter { $0 != trimmed }
        history.insert(trimmed, at: 0)
        if history.count > 3 { history = Array(history.prefix(3)) }
        if let encoded = try? JSONEncoder().encode(history) {
            recentSearchesData = encoded
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

    private func handleTransfersViewAppear() {
        applyGlobalAggregationSafetyFallbackIfNeeded()
        triggerInitialLoadIfNeeded()
        debouncedSearchText = searchText
        scheduleFilteredTasksRecompute()
        scheduleUniqueTrackersRecompute()
        syncOverlayLoadingVisibility()
    }

    private func handleSelectedTabChanged(_ newValue: AppTab) {
        if newValue == .transfers {
            triggerInitialLoadIfNeeded()
        }
        scheduleFilteredTasksRecompute(showOverlayHint: newValue == .transfers)
        scheduleUniqueTrackersRecompute()
        syncOverlayLoadingVisibility()
    }

    private func handleTransfersViewDisappear() {
        searchDebounceTask?.cancel()
        filterComputationTask?.cancel()
        trackerListComputationTask?.cancel()
        overlayLoadingDelayTask?.cancel()
        isFilteringTasks = false
        shouldHintOverlayLoadingForCurrentFilterPass = false
        isOverlayLoadingVisible = false
    }

    private func applyGlobalAggregationSafetyFallbackIfNeeded() {
        guard !canUseGlobalTaskAggregation else { return }
        guard appStateManager.activeServerId == nil else { return }
        guard let firstServerID = appStateManager.servers.first?.id else { return }
        appStateManager.activeServerId = firstServerID
    }

    private var transfersRootContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 0. 服务器状态栏 (Pinned Top)
                ServerStatusBar(appStateManager: appStateManager)
                    .background(Color(uiColor: .systemBackground))

                // 0.5. Quick Filter Bar (Capsule) - Hide when editing
                if !isEditing {
                    QuickFilterBar(selectedStatus: $selectedStatus)
                        .padding(.bottom, 8)
                        .background(Color(uiColor: .systemBackground))
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .bottom
                        )
                }

                // 1. 任务列表
                tasksListSection
            }

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
    }

    @ToolbarContentBuilder
    private var transfersToolbarContent: some ToolbarContent {
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
                    if canUseGlobalTaskAggregation {
                        Button {
                            appStateManager.activeServerId = nil
                        } label: {
                            Label(LanguageManager.shared.localized("All Servers"), systemImage: "rectangle.stack.fill")
                        }
                    }

                    ForEach(appStateManager.servers) { server in
                        Button {
                            appStateManager.activeServerId = server.id
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
                    ServerBrandIcon(type: appStateManager.activeServerType, size: 22)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !isEditing {
                    FilterMenuView(
                        sortOption: $sortOption,
                        sortAscending: $sortAscending,
                        selectedTracker: $selectedTracker,
                        uniqueTrackers: uniqueTrackers,
                        isFilterActive: isFilterActive,
                        allTrackersToken: Self.allTrackersToken
                    )
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

    @ViewBuilder
    private var tasksListSection: some View {
        if shouldShowTasksLoadingState {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text(LanguageManager.shared.localized("Loading..."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        } else if filteredTasks.isEmpty {
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
                    taskRowCell(task)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await appStateManager.refreshData()
            }
            .overlay(alignment: .top) {
                tasksInlineLoadingOverlay
            }
        }
    }

    private func taskRowCell(_ task: TorrentTask) -> some View {
        TorrentRowView(
            task: task,
            isSelected: selectedTaskHashes.contains(task.id),
            isEditing: isEditing,
            toggleSelection: {
                toggleSelection(for: task.id)
            },
            onShowActionSheet: { selectedTask, posterURL in
                selectedTorrentPosterURL = posterURL
                selectedTorrentForAction = selectedTask
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

    @ViewBuilder
    private var tasksInlineLoadingOverlay: some View {
        if isOverlayLoadingVisible {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(LanguageManager.shared.localized("Loading..."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            .padding(.top, 10)
            .allowsHitTesting(false)
        }
    }

    private func triggerInitialLoadIfNeeded() {
        guard isTransfersTabActive else { return }
        guard !hasAttemptedInitialLoad else { return }
        guard appStateManager.allTasks.isEmpty else {
            hasAttemptedInitialLoad = true
            return
        }
        guard !appStateManager.servers.isEmpty else { return }

        hasAttemptedInitialLoad = true
        Task {
            await appStateManager.refreshData()
        }
    }

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()

        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }

        let nextValue = searchText
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedSearchText = nextValue
            }
        }
    }

    private func scheduleFilteredTasksRecompute(showOverlayHint: Bool = false) {
        filterComputationTask?.cancel()

        let sourceTasks = isTransfersTabActive ? appStateManager.displayedTasks : []
        let status = selectedStatus
        let search = debouncedSearchText
        let tracker = selectedTracker
        let sort = sortOption
        let ascending = sortAscending
        let aliasMapSnapshot = TrackerAliasManager.shared.aliasMap

        shouldHintOverlayLoadingForCurrentFilterPass = showOverlayHint
        isFilteringTasks = true

        filterComputationTask = Task {
            let computed = await Self.computeFilteredTasksOnBackground(
                sourceTasks: sourceTasks,
                selectedStatus: status,
                searchText: search,
                selectedTracker: tracker,
                allTrackersToken: Self.allTrackersToken,
                sortOption: sort,
                sortAscending: ascending,
                aliasMap: aliasMapSnapshot
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                filteredTasks = computed
                isFilteringTasks = false
                shouldHintOverlayLoadingForCurrentFilterPass = false
            }
        }
    }

    private func syncOverlayLoadingVisibility() {
        overlayLoadingDelayTask?.cancel()

        guard shouldRequestOverlayTasksLoadingState else {
            isOverlayLoadingVisible = false
            return
        }

        guard !isOverlayLoadingVisible else { return }

        overlayLoadingDelayTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.shouldRequestOverlayTasksLoadingState {
                    self.isOverlayLoadingVisible = true
                }
            }
        }
    }

    private func scheduleUniqueTrackersRecompute() {
        trackerListComputationTask?.cancel()

        guard isTransfersTabActive else {
            uniqueTrackersCache = [Self.allTrackersToken]
            return
        }

        let sourceTasks = appStateManager.allTasks

        trackerListComputationTask = Task {
            let computed = await Self.computeUniqueTrackersOnBackground(
                sourceTasks: sourceTasks,
                allTrackersToken: Self.allTrackersToken
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                uniqueTrackersCache = computed
            }
        }
    }

    private static func computeFilteredTasksOnBackground(
        sourceTasks: [TorrentTask],
        selectedStatus: TaskStatusFilter,
        searchText: String,
        selectedTracker: String,
        allTrackersToken: String,
        sortOption: SortOption,
        sortAscending: Bool,
        aliasMap: [String: String] = [:]
    ) async -> [TorrentTask] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var tasks = sourceTasks

                if selectedStatus != .all {
                    tasks = tasks.filter { selectedStatus.matches($0) }
                }

                if !searchText.isEmpty {
                    tasks = tasks.filter { task in
                        if task.name.localizedCaseInsensitiveContains(searchText) ||
                           task.trackerHost.localizedCaseInsensitiveContains(searchText) {
                            return true
                        }
                        let alias = aliasMap[task.trackerHost.lowercased()] ?? ""
                        return !alias.isEmpty && alias.localizedCaseInsensitiveContains(searchText)
                    }
                }

                if selectedTracker != allTrackersToken {
                    tasks = tasks.filter { $0.trackerHost == selectedTracker }
                }

                let sorted = tasks.sorted { t1, t2 in
                    let result: Bool
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

                continuation.resume(returning: sorted)
            }
        }
    }

    private static func computeUniqueTrackersOnBackground(
        sourceTasks: [TorrentTask],
        allTrackersToken: String
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let hosts = sourceTasks.map(\.trackerHost)
                let unique = Set(hosts)
                continuation.resume(returning: [allTrackersToken] + unique.sorted())
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

// MARK: - Filter Menu Component
struct FilterMenuView: View {
    @Binding var sortOption: SortOption
    @Binding var sortAscending: Bool
    @Binding var selectedTracker: String
    let uniqueTrackers: [String]
    let isFilterActive: Bool
    let allTrackersToken: String

    var body: some View {
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
                            tracker == allTrackersToken
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
