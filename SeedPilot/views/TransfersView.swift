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

    @State private var viewModel = TransfersViewModel()

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

    @MainActor
    private var serverMenuSnapshots: [ServerMenuSnapshot] {
        appStateManager.servers.map(ServerMenuSnapshot.init)
    }

    private var navigationTitle: String {
        if isEditing {
            return viewModel.selectedTaskHashes.isEmpty
                ? LanguageManager.shared.localized("Select Items")
                : String(
                    format: LanguageManager.shared.localized("Selected Items Count Format"),
                    locale: .current,
                    viewModel.selectedTaskHashes.count
                )
        } else {
            return appStateManager.activeServerName ?? LanguageManager.shared.localized("Transfers")
        }
    }

    var body: some View {
        transfersPresentedView
    }

    private var transfersPresentedView: some View {
        transfersLifecycleBoundView
            .sheet(isPresented: $viewModel.showingAddMagnet) {
                AddTorrentView()
            }
            .sheet(item: $viewModel.selectedTorrentForAction) { selectedTask in
                TorrentActionSheetView(
                    task: selectedTask,
                    posterURL: viewModel.selectedTorrentPosterURL,
                    appStateManager: appStateManager,
                    onPosterChanged: {
                        TMDBService.shared.clearCache(for: selectedTask.hash, name: selectedTask.name)
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
            .sheet(item: $viewModel.activeSheet) { sheet in
                filterSheetView(for: sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    private var transfersLifecycleBoundView: some View {
        transfersLifecycleBoundViewPart1
            .onChange(of: viewModel.selectedStatuses) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.selectedCategories) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.selectedTags) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.sortOption) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.sortAscending) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.selectedTrackers) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.scheduleSearchDebounce()
            }
            .onChange(of: viewModel.debouncedSearchText) { _, _ in
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: viewModel.isFilteringTasks) { _, _ in
                viewModel.syncOverlayLoadingVisibility(isTransfersTabActive: isTransfersTabActive)
            }
            .onChange(of: viewModel.filteredTasks.count) { _, _ in
                viewModel.syncOverlayLoadingVisibility(isTransfersTabActive: isTransfersTabActive)
            }
            .onDisappear {
                viewModel.handleTransfersViewDisappear()
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
                viewModel.scheduleFilteredTasksRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
                viewModel.scheduleFilterOptionsRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
            }
            .onChange(of: appStateManager.activeServerId) { _, _ in
                if !isCategoryFilterSupported {
                    viewModel.selectedCategories.removeAll()
                    if viewModel.activeSheet == .category {
                        viewModel.activeSheet = nil
                    }
                }
                viewModel.scheduleFilteredTasksRecompute(showOverlayHint: true, isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
                viewModel.scheduleFilterOptionsRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
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
                        text: $viewModel.searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: LanguageManager.shared.localized("Search Torrents or Trackers")
                    )
                    .searchSuggestions {
                        if viewModel.searchText.isEmpty {
                            ForEach(recentSearches, id: \.self) { term in
                                Label(term, systemImage: "clock.arrow.circlepath")
                                    .searchCompletion(term)
                            }
                        }
                    }
                    .onSubmit(of: .search) {
                        saveSearchTerm(viewModel.searchText)
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
    private func handleTransfersViewAppear() {
        applyGlobalAggregationSafetyFallbackIfNeeded()
        triggerInitialLoadIfNeeded()
        viewModel.handleTransfersViewAppear(appStateManager: appStateManager, isTransfersTabActive: isTransfersTabActive)
    }

    private func handleSelectedTabChanged(_ newValue: AppTab) {
        if newValue == .transfers {
            triggerInitialLoadIfNeeded()
        }
        viewModel.handleSelectedTabChanged(newValue, appStateManager: appStateManager)
    }

    private func applyGlobalAggregationSafetyFallbackIfNeeded() {
        guard !canUseGlobalTaskAggregation else { return }
        guard appStateManager.activeServerId == nil else { return }
        guard let firstServerID = appStateManager.servers.first?.id else { return }
        appStateManager.activeServerId = firstServerID
    }

    private func triggerInitialLoadIfNeeded() {
        guard isTransfersTabActive else { return }
        guard !viewModel.hasAttemptedInitialLoad else { return }
        guard appStateManager.allTasks.isEmpty else {
            viewModel.hasAttemptedInitialLoad = true
            return
        }
        guard !appStateManager.servers.isEmpty else { return }

        viewModel.hasAttemptedInitialLoad = true
        Task {
            await appStateManager.refreshData()
        }
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
                        selectedStatuses: $viewModel.selectedStatuses,
                        selectedCategories: $viewModel.selectedCategories,
                        selectedTags: $viewModel.selectedTags,
                        selectedTrackers: $viewModel.selectedTrackers,
                        activeSheet: $viewModel.activeSheet,
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

            if !isEditing {
                Button {
                    viewModel.showingAddMagnet = true
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
                    if viewModel.selectedTaskHashes.count == viewModel.filteredTasks.count {
                        viewModel.selectedTaskHashes.removeAll()
                    } else {
                        viewModel.selectedTaskHashes = Set(viewModel.filteredTasks.map { $0.id })
                    }
                } label: {
                    Text(
                        viewModel.selectedTaskHashes.count == viewModel.filteredTasks.count
                        ? LanguageManager.shared.localized("Deselect All")
                        : LanguageManager.shared.localized("Select All")
                    )
                }
            } else {
                ServerDropdownMenuView(
                    activeServerType: appStateManager.activeServerType,
                    activeServerID: appStateManager.activeServerId,
                    serverMenuSnapshots: serverMenuSnapshots,
                    canUseGlobalTaskAggregation: canUseGlobalTaskAggregation,
                    isDisabled: appStateManager.servers.isEmpty || emptyStatesView.shouldShowServerEmptyState,
                    onSelectServer: { serverID in
                        appStateManager.activeServerId = serverID
                    }
                )
                .equatable()
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !isEditing {
                    SortMenuView(
                        sortOption: $viewModel.sortOption,
                        sortAscending: $viewModel.sortAscending
                    )
                }

                if isEditing {
                    BatchActionMenu(
                        selectedTaskHashes: $viewModel.selectedTaskHashes,
                        isEditing: Binding(
                            get: { editMode?.wrappedValue == .active },
                            set: { if !$0 { editMode?.wrappedValue = .inactive } }
                        )
                    )

                    Button(LanguageManager.shared.localized("Done")) {
                        withAnimation {
                            editMode?.wrappedValue = .inactive
                            viewModel.selectedTaskHashes.removeAll()
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
    
    // Using simple var to be able to refer to boolean flags inside empty state computations without redefining them
    private var emptyStatesView: TransfersEmptyStatesView {
        TransfersEmptyStatesView(viewModel: viewModel, appStateManager: appStateManager)
    }

    @ViewBuilder
    private var tasksListSection: some View {
        if emptyStatesView.shouldShowServerEmptyState || emptyStatesView.shouldShowTasksLoadingState || (viewModel.isFilteringTasks && viewModel.filteredTasks.isEmpty) || viewModel.filteredTasks.isEmpty {
            emptyStatesView
        } else {
            TransfersListView(viewModel: viewModel, appStateManager: appStateManager, isEditing: isEditing)
        }
    }

    private func filterSheetView(for sheet: ActiveFilterSheet) -> some View {
        NavigationStack {
            List {
                switch sheet {
                case .status:
                    filterSheetRow(
                        title: TaskStatusFilter.all.title,
                        isSelected: viewModel.selectedStatuses.isEmpty
                    ) {
                        viewModel.selectedStatuses.removeAll()
                    }

                    ForEach(TaskStatusFilter.allCases.filter { $0 != .all }) { status in
                        filterSheetRow(
                            title: status.title,
                            isSelected: viewModel.selectedStatuses.contains(status)
                        ) {
                            if viewModel.selectedStatuses.contains(status) {
                                viewModel.selectedStatuses.remove(status)
                            } else {
                                viewModel.selectedStatuses.insert(status)
                            }
                        }
                    }
                case .category:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Categories"),
                        isSelected: viewModel.selectedCategories.isEmpty
                    ) {
                        viewModel.selectedCategories.removeAll()
                    }

                    ForEach(viewModel.uniqueCategories(isTransfersTabActive: isTransfersTabActive).filter { $0 != TransfersViewModel.allCategoriesToken }, id: \.self) { category in
                        filterSheetRow(
                            title: category,
                            isSelected: viewModel.selectedCategories.contains(category)
                        ) {
                            if viewModel.selectedCategories.contains(category) {
                                viewModel.selectedCategories.remove(category)
                            } else {
                                viewModel.selectedCategories.insert(category)
                            }
                        }
                    }
                case .tag:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Tags"),
                        isSelected: viewModel.selectedTags.isEmpty
                    ) {
                        viewModel.selectedTags.removeAll()
                    }

                    ForEach(viewModel.uniqueTags(isTransfersTabActive: isTransfersTabActive).filter { $0 != TransfersViewModel.allTagsToken }, id: \.self) { tag in
                        filterSheetRow(
                            title: tag,
                            isSelected: viewModel.selectedTags.contains(tag)
                        ) {
                            if viewModel.selectedTags.contains(tag) {
                                viewModel.selectedTags.remove(tag)
                            } else {
                                viewModel.selectedTags.insert(tag)
                            }
                        }
                    }
                case .tracker:
                    filterSheetRow(
                        title: LanguageManager.shared.localized("All Trackers"),
                        isSelected: viewModel.selectedTrackers.isEmpty
                    ) {
                        viewModel.selectedTrackers.removeAll()
                    }

                    ForEach(viewModel.uniqueTrackers(isTransfersTabActive: isTransfersTabActive).filter { $0 != TransfersViewModel.allTrackersToken }, id: \.self) { tracker in
                        filterSheetRow(
                            title: tracker,
                            isSelected: viewModel.selectedTrackers.contains(tracker)
                        ) {
                            if viewModel.selectedTrackers.contains(tracker) {
                                viewModel.selectedTrackers.remove(tracker)
                            } else {
                                viewModel.selectedTrackers.insert(tracker)
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
                            viewModel.activeSheet = nil
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

#Preview {
    TransfersView()
        .environment(AppStateManager())
}
