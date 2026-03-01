//
//  TransfersView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

enum ActiveFilterSheet: String, Identifiable {
    case status
    case category
    case tag
    case tracker

    var id: String { rawValue }
}

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
    @State private var uniqueCategoriesCache: [String] = [Self.allCategoriesToken]
    @State private var uniqueTagsCache: [String] = [Self.allTagsToken]
    @State private var uniqueTrackersCache: [String] = [Self.allTrackersToken]
    @State private var isFilteringTasks = false
    @State private var shouldHintOverlayLoadingForCurrentFilterPass = false
    @State private var isOverlayLoadingVisible = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var filterComputationTask: Task<Void, Never>?
    @State private var filterOptionsComputationTask: Task<Void, Never>?
    @State private var overlayLoadingDelayTask: Task<Void, Never>?

    // 状态筛选
    @State private var selectedStatuses: Set<TaskStatusFilter> = []
    @State private var selectedCategories: Set<String> = []
    @State private var selectedTags: Set<String> = []
    @State private var selectedTrackers: Set<String> = []
    @State private var activeSheet: ActiveFilterSheet?

    @State private var sortOption: SortOption = .dateAdded
    @State private var sortAscending: Bool = false // Default Descending (Newest first)

    private static let allCategoriesToken = "__ALL_CATEGORIES__"
    private static let allTagsToken = "__ALL_TAGS__"
    private static let allTrackersToken = "__ALL_TRACKERS__"

    // Batch Action States
    // ... (unchanged)

    // 添加任务
    @State private var showingAddMagnet = false
    @State private var selectedTorrentForAction: TorrentTask?
    @State private var selectedTorrentPosterURL: URL?

    var uniqueCategories: [String] {
        guard isTransfersTabActive else { return [Self.allCategoriesToken] }
        return uniqueCategoriesCache
    }

    var uniqueTags: [String] {
        guard isTransfersTabActive else { return [Self.allTagsToken] }
        return uniqueTagsCache
    }

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

    private var isCategoryFilterSupported: Bool {
        appStateManager.activeServerType != .transmission
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
        guard !appStateManager.servers.isEmpty else { return false }

        // Keep full-screen loading for first load only; avoid empty-state flicker during periodic refresh/filter passes.
        guard !appStateManager.hasInitialDataLoaded else { return false }
        return appStateManager.isRefreshingTasks || isFilteringTasks || appStateManager.allTasks.isEmpty
    }

    private var shouldShowServerEmptyState: Bool {
        if appStateManager.servers.isEmpty { return true }
        if let id = appStateManager.activeServerId,
           let server = appStateManager.servers.first(where: { $0.id == id }),
           server.isOnline == false,
           appStateManager.hasInitialDataLoaded {
            return true
        }
        return false
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
            .sheet(item: $activeSheet) { sheet in
                filterSheetView(for: sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    private var transfersLifecycleBoundView: some View {
        transfersLifecycleBoundViewPart1
            .onChange(of: selectedStatuses) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: selectedCategories) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: selectedTags) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: sortOption) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: sortAscending) { _, _ in
                scheduleFilteredTasksRecompute(showOverlayHint: true)
            }
            .onChange(of: selectedTrackers) { _, _ in
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
                scheduleFilterOptionsRecompute()
            }
            .onChange(of: appStateManager.activeServerId) { _, _ in
                if !isCategoryFilterSupported {
                    selectedCategories.removeAll()
                    if activeSheet == .category {
                        activeSheet = nil
                    }
                }
                scheduleFilteredTasksRecompute(showOverlayHint: true)
                scheduleFilterOptionsRecompute()
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
        scheduleFilterOptionsRecompute()
        syncOverlayLoadingVisibility()
    }

    private func handleSelectedTabChanged(_ newValue: AppTab) {
        if newValue == .transfers {
            triggerInitialLoadIfNeeded()
        }
        scheduleFilteredTasksRecompute(showOverlayHint: newValue == .transfers)
        scheduleFilterOptionsRecompute()
        syncOverlayLoadingVisibility()
    }

    private func handleTransfersViewDisappear() {
        searchDebounceTask?.cancel()
        filterComputationTask?.cancel()
        filterOptionsComputationTask?.cancel()
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

                // 0.5. Top Filter Menus - Fixed Position
                if !isEditing {
                    TorrentFilterMenuBar(
                        selectedStatuses: $selectedStatuses,
                        selectedCategories: $selectedCategories,
                        selectedTags: $selectedTags,
                        selectedTrackers: $selectedTrackers,
                        activeSheet: $activeSheet,
                        isCategoryFilterSupported: isCategoryFilterSupported
                    )
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
                .disabled(appStateManager.servers.isEmpty || shouldShowServerEmptyState)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !isEditing {
                    SortMenuView(
                        sortOption: $sortOption,
                        sortAscending: $sortAscending
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
        if shouldShowServerEmptyState {
            serverEmptyStateView
        } else if shouldShowTasksLoadingState {
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

    private var serverEmptyStateView: some View {
        ContentUnavailableView {
            Label(
                LanguageManager.shared.localized("No Available Server"),
                systemImage: "server.rack"
            )
        } description: {
            Text(LanguageManager.shared.localized("Please check your server configuration or network status."))
        } actions: {
            Button {
                appStateManager.selectedTab = .settings
            } label: {
                Text(LanguageManager.shared.localized("Go to Server Settings"))
            }
            .buttonStyle(.borderedProminent)
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
        .equatable()
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
        let statuses = selectedStatuses
        let categories = selectedCategories
        let tags = selectedTags
        let search = debouncedSearchText
        let trackers = selectedTrackers
        let sort = sortOption
        let ascending = sortAscending
        let categoryFilterSupported = isCategoryFilterSupported
        let aliasMapSnapshot = TrackerAliasManager.shared.aliasMap
        let startUptime = DispatchTime.now().uptimeNanoseconds

        shouldHintOverlayLoadingForCurrentFilterPass = showOverlayHint
        isFilteringTasks = true

        filterComputationTask = Task {
            let computed = await Self.computeFilteredTasksOnBackground(
                sourceTasks: sourceTasks,
                selectedStatuses: statuses,
                selectedCategories: categories,
                selectedTags: tags,
                searchText: search,
                selectedTrackers: trackers,
                isCategoryFilterSupported: categoryFilterSupported,
                sortOption: sort,
                sortAscending: ascending,
                aliasMap: aliasMapSnapshot
            )
            guard !Task.isCancelled else { return }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
#if DEBUG
            if sourceTasks.count >= 50_000 {
                let elapsedText = String(format: "%.1f", elapsedMs)
                print(
                    "Transfers filter pass: source=\(sourceTasks.count) result=\(computed.count) elapsedMs=\(elapsedText)"
                )
            }
#endif
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

    private func scheduleFilterOptionsRecompute() {
        filterOptionsComputationTask?.cancel()

        guard isTransfersTabActive else {
            uniqueCategoriesCache = [Self.allCategoriesToken]
            uniqueTagsCache = [Self.allTagsToken]
            uniqueTrackersCache = [Self.allTrackersToken]
            return
        }

        let sourceTasks = appStateManager.displayedTasks

        filterOptionsComputationTask = Task {
            let computed = await Self.computeFilterOptionsOnBackground(
                sourceTasks: sourceTasks,
                allCategoriesToken: Self.allCategoriesToken,
                allTagsToken: Self.allTagsToken,
                allTrackersToken: Self.allTrackersToken
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                uniqueCategoriesCache = computed.categories
                uniqueTagsCache = computed.tags
                uniqueTrackersCache = computed.trackers

                if !isCategoryFilterSupported {
                    selectedCategories.removeAll()
                } else {
                    let categoryOptions = Set(computed.categories.dropFirst())
                    selectedCategories = Set(selectedCategories.filter(categoryOptions.contains))
                }

                let tagOptions = Set(computed.tags.dropFirst())
                let trackerOptions = Set(computed.trackers.dropFirst())
                selectedTags = Set(selectedTags.filter(tagOptions.contains))
                selectedTrackers = Set(selectedTrackers.filter(trackerOptions.contains))
            }
        }
    }

    private static func computeFilteredTasksOnBackground(
        sourceTasks: [TorrentTask],
        selectedStatuses: Set<TaskStatusFilter>,
        selectedCategories: Set<String>,
        selectedTags: Set<String>,
        searchText: String,
        selectedTrackers: Set<String>,
        isCategoryFilterSupported: Bool,
        sortOption: SortOption,
        sortAscending: Bool,
        aliasMap: [String: String] = [:]
    ) async -> [TorrentTask] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let computed = Self.computeFilteredTasks(
                    sourceTasks: sourceTasks,
                    selectedStatuses: selectedStatuses,
                    selectedCategories: selectedCategories,
                    selectedTags: selectedTags,
                    searchText: searchText,
                    selectedTrackers: selectedTrackers,
                    isCategoryFilterSupported: isCategoryFilterSupported,
                    sortOption: sortOption,
                    sortAscending: sortAscending,
                    aliasMap: aliasMap
                )
                continuation.resume(returning: computed)
            }
        }
    }

    private static func computeFilteredTasks(
        sourceTasks: [TorrentTask],
        selectedStatuses: Set<TaskStatusFilter>,
        selectedCategories: Set<String>,
        selectedTags: Set<String>,
        searchText: String,
        selectedTrackers: Set<String>,
        isCategoryFilterSupported: Bool,
        sortOption: SortOption,
        sortAscending: Bool,
        aliasMap: [String: String] = [:]
    ) -> [TorrentTask] {
        guard !sourceTasks.isEmpty else { return [] }

        let effectiveStatuses = selectedStatuses.filter { $0 != .all }
        let statusFilterEnabled = !effectiveStatuses.isEmpty
        let normalizedCategories = Set(
            selectedCategories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let categoryFilterEnabled = isCategoryFilterSupported && !normalizedCategories.isEmpty

        let normalizedTags = Set(
            selectedTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let tagFilterEnabled = !normalizedTags.isEmpty

        let normalizedTrackers = Set(
            selectedTrackers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let trackerFilterEnabled = !normalizedTrackers.isEmpty

        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let searchEnabled = !normalizedSearch.isEmpty
        let normalizedAliasMap: [String: String] = searchEnabled
            ? aliasMap.reduce(into: [String: String](minimumCapacity: aliasMap.count)) { partial, entry in
                partial[entry.key.lowercased()] = entry.value.lowercased()
            }
            : [:]

        var filtered: [TorrentTask] = []
        filtered.reserveCapacity(sourceTasks.count)

        for task in sourceTasks {
            if statusFilterEnabled && !effectiveStatuses.contains(where: { $0.matches(task) }) {
                continue
            }

            if categoryFilterEnabled {
                let taskCategory = task.category
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if !normalizedCategories.contains(taskCategory) {
                    continue
                }
            }

            if tagFilterEnabled && !containsAnyTag(task.tags, normalizedTags: normalizedTags) {
                continue
            }

            let trackerHostLower = task.trackerHost.lowercased()
            if trackerFilterEnabled && !normalizedTrackers.contains(trackerHostLower) {
                continue
            }

            if searchEnabled {
                if task.name.lowercased().contains(normalizedSearch) ||
                    trackerHostLower.contains(normalizedSearch) {
                    filtered.append(task)
                    continue
                }

                let alias = normalizedAliasMap[trackerHostLower] ?? ""
                if alias.contains(normalizedSearch) {
                    filtered.append(task)
                    continue
                }

                continue
            }

            filtered.append(task)
        }

        sortTasks(
            &filtered,
            by: sortOption,
            ascending: sortAscending
        )
        return filtered
    }

    private static func sortTasks(
        _ tasks: inout [TorrentTask],
        by sortOption: SortOption,
        ascending: Bool
    ) {
        tasks.sort { lhs, rhs in
            switch sortOption {
            case .dateAdded:
                if lhs.addedTime == rhs.addedTime { return lhs.id < rhs.id }
                return ascending ? lhs.addedTime < rhs.addedTime : lhs.addedTime > rhs.addedTime
            case .name:
                let compare = lhs.name.localizedStandardCompare(rhs.name)
                if compare == .orderedSame { return lhs.id < rhs.id }
                return ascending ? compare == .orderedAscending : compare == .orderedDescending
            case .downloadSpeed:
                if lhs.downloadSpeed == rhs.downloadSpeed { return lhs.id < rhs.id }
                return ascending ? lhs.downloadSpeed < rhs.downloadSpeed : lhs.downloadSpeed > rhs.downloadSpeed
            case .uploadSpeed:
                if lhs.uploadSpeed == rhs.uploadSpeed { return lhs.id < rhs.id }
                return ascending ? lhs.uploadSpeed < rhs.uploadSpeed : lhs.uploadSpeed > rhs.uploadSpeed
            case .size:
                if lhs.size == rhs.size { return lhs.id < rhs.id }
                return ascending ? lhs.size < rhs.size : lhs.size > rhs.size
            case .progress:
                if lhs.progress == rhs.progress { return lhs.id < rhs.id }
                return ascending ? lhs.progress < rhs.progress : lhs.progress > rhs.progress
            }
        }
    }

    private static func splitTags(_ rawTags: String) -> [String] {
        rawTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func containsAnyTag(_ rawTags: String, normalizedTags: Set<String>) -> Bool {
        guard !normalizedTags.isEmpty else { return true }

        for token in rawTags.split(separator: ",") {
            let normalized = token
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedTags.contains(normalized) {
                return true
            }
        }
        return false
    }

    private struct TaskFilterOptions: Sendable {
        let categories: [String]
        let tags: [String]
        let trackers: [String]
    }

    private static func computeFilterOptionsOnBackground(
        sourceTasks: [TorrentTask],
        allCategoriesToken: String,
        allTagsToken: String,
        allTrackersToken: String
    ) async -> TaskFilterOptions {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let computed = Self.computeFilterOptions(
                    sourceTasks: sourceTasks,
                    allCategoriesToken: allCategoriesToken,
                    allTagsToken: allTagsToken,
                    allTrackersToken: allTrackersToken
                )
                continuation.resume(returning: computed)
            }
        }
    }

    private static func computeFilterOptions(
        sourceTasks: [TorrentTask],
        allCategoriesToken: String,
        allTagsToken: String,
        allTrackersToken: String
    ) -> TaskFilterOptions {
        var categories = Set<String>()
        var tags = Set<String>()
        var trackers = Set<String>()
        categories.reserveCapacity(min(sourceTasks.count, 2048))
        tags.reserveCapacity(min(sourceTasks.count, 4096))
        trackers.reserveCapacity(min(sourceTasks.count, 4096))

        for task in sourceTasks {
            let category = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !category.isEmpty {
                categories.insert(category)
            }

            let taskTags = splitTags(task.tags)
            if !taskTags.isEmpty {
                tags.formUnion(taskTags)
            }

            let host = task.trackerHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty, host != "--" {
                trackers.insert(host)
            }
        }

        let sortedCategories = categories.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let sortedTags = tags.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let sortedTrackers = trackers.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return TaskFilterOptions(
            categories: [allCategoriesToken] + sortedCategories,
            tags: [allTagsToken] + sortedTags,
            trackers: [allTrackersToken] + sortedTrackers
        )
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

    private func filterSheetView(for sheet: ActiveFilterSheet) -> some View {
        NavigationStack {
            List {
                switch sheet {
                case .status:
                    filterSheetRow(
                        title: TaskStatusFilter.all.title,
                        isSelected: selectedStatuses.isEmpty
                    ) {
                        selectedStatuses.removeAll()
                    }

                    ForEach(TaskStatusFilter.allCases.filter { $0 != .all }) { status in
                        filterSheetRow(
                            title: status.title,
                            isSelected: selectedStatuses.contains(status)
                        ) {
                            if selectedStatuses.contains(status) {
                                selectedStatuses.remove(status)
                            } else {
                                selectedStatuses.insert(status)
                            }
                        }
                    }
                case .category:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Categories"),
                        isSelected: selectedCategories.isEmpty
                    ) {
                        selectedCategories.removeAll()
                    }

                    ForEach(uniqueCategories.filter { $0 != Self.allCategoriesToken }, id: \.self) { category in
                        filterSheetRow(
                            title: category,
                            isSelected: selectedCategories.contains(category)
                        ) {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                    }
                case .tag:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Tags"),
                        isSelected: selectedTags.isEmpty
                    ) {
                        selectedTags.removeAll()
                    }

                    ForEach(uniqueTags.filter { $0 != Self.allTagsToken }, id: \.self) { tag in
                        filterSheetRow(
                            title: tag,
                            isSelected: selectedTags.contains(tag)
                        ) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    }
                case .tracker:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Trackers"),
                        isSelected: selectedTrackers.isEmpty
                    ) {
                        selectedTrackers.removeAll()
                    }

                    ForEach(uniqueTrackers.filter { $0 != Self.allTrackersToken }, id: \.self) { tracker in
                        filterSheetRow(
                            title: tracker,
                            isSelected: selectedTrackers.contains(tracker)
                        ) {
                            if selectedTrackers.contains(tracker) {
                                selectedTrackers.remove(tracker)
                            } else {
                                selectedTrackers.insert(tracker)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(filterSheetTitle(for: sheet))
            .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LanguageManager.shared.localized("Done")) {
                            activeSheet = nil
                        }
                    }
                }
        }
    }

    private func filterSheetRow(
        title: String,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button {
            onSelect()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func filterSheetTitle(for sheet: ActiveFilterSheet) -> String {
        switch sheet {
        case .status:
            return LanguageManager.shared.localized("Status")
        case .category:
            return LanguageManager.shared.localized("Category")
        case .tag:
            return LanguageManager.shared.localized("Tags")
        case .tracker:
            return LanguageManager.shared.localized("Tracker")
        }
    }

}

// MARK: - Top Filter Menus
struct TorrentFilterMenuBar: View {
    @Binding var selectedStatuses: Set<TaskStatusFilter>
    @Binding var selectedCategories: Set<String>
    @Binding var selectedTags: Set<String>
    @Binding var selectedTrackers: Set<String>
    @Binding var activeSheet: ActiveFilterSheet?

    let isCategoryFilterSupported: Bool

    private var selectedStatusCount: Int {
        selectedStatuses.filter { $0 != .all }.count
    }

    private var statusTitle: String {
        let base = LanguageManager.shared.localized("Status")
        if selectedStatusCount > 1 {
            return "\(base)(\(selectedStatusCount))"
        }
        guard selectedStatusCount == 1,
              let only = selectedStatuses.first(where: { $0 != .all }) else {
            return base
        }
        return only.title
    }

    private var categoryTitle: String {
        let base = LanguageManager.shared.localized("Category")
        if selectedCategories.count > 1 {
            return "\(base)(\(selectedCategories.count))"
        }
        guard selectedCategories.count == 1, let only = selectedCategories.first else {
            return base
        }
        return only
    }

    private var tagTitle: String {
        let base = LanguageManager.shared.localized("Tags")
        if selectedTags.count > 1 {
            return "\(base)(\(selectedTags.count))"
        }
        guard selectedTags.count == 1, let only = selectedTags.first else {
            return base
        }
        return only
    }

    private var trackerTitle: String {
        let base = LanguageManager.shared.localized("Tracker")
        if selectedTrackers.count > 1 {
            return "\(base)(\(selectedTrackers.count))"
        }
        guard selectedTrackers.count == 1, let only = selectedTrackers.first else {
            return base
        }
        return only
    }

    var body: some View {
        HStack(spacing: 0) {
            statusButton
            filterDivider

            if isCategoryFilterSupported {
                categoryButton
                filterDivider
            }

            tagButton
            filterDivider
            trackerButton
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var filterDivider: some View {
        Divider()
            .frame(height: 14)
            .overlay(Color(uiColor: .separator).opacity(0.3))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusButton: some View {
        buttonContainer {
            activeSheet = .status
        } label: {
            FilterMenuControl(title: statusTitle, isActive: !selectedStatuses.isEmpty)
        }
    }

    @ViewBuilder
    private var categoryButton: some View {
        buttonContainer {
            activeSheet = .category
        } label: {
            FilterMenuControl(title: categoryTitle, isActive: !selectedCategories.isEmpty)
        }
    }

    @ViewBuilder
    private var tagButton: some View {
        buttonContainer {
            activeSheet = .tag
        } label: {
            FilterMenuControl(title: tagTitle, isActive: !selectedTags.isEmpty)
        }
    }

    @ViewBuilder
    private var trackerButton: some View {
        buttonContainer {
            activeSheet = .tracker
        } label: {
            FilterMenuControl(title: trackerTitle, isActive: !selectedTrackers.isEmpty)
        }
    }

    private func buttonContainer(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.automatic)
        .frame(maxWidth: .infinity)
    }
}

struct FilterMenuControl: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(isActive ? .subheadline.weight(.semibold) : .subheadline.weight(.regular))
        .foregroundColor(isActive ? .accentColor : .secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Sort Menu
struct SortMenuView: View {
    @Binding var sortOption: SortOption
    @Binding var sortAscending: Bool

    var body: some View {
        Menu {
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
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 17, weight: .semibold))
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
