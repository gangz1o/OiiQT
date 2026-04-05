import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class TransfersViewModel {
    private static let scrollRefreshSource = "transfers.list"

    // MARK: - Search & Filter State
    var searchText = ""
    var debouncedSearchText = ""
    var selectedStatuses: Set<TaskStatusFilter> = []
    var selectedCategories: Set<String> = []
    var selectedTags: Set<String> = []
    var selectedTrackers: Set<String> = []
    var activeSheet: ActiveFilterSheet?

    // MARK: - Sort State
    var sortOption: SortOption = .dateAdded
    var sortAscending: Bool = false

    // MARK: - Render Snapshot
    var filteredTaskIDs: [String] = []
    var selectedTaskHashes = Set<String>()

    // MARK: - Filter Caches
    var uniqueCategoriesCache: [String] = [allCategoriesToken]
    var uniqueTagsCache: [String] = [allTagsToken]
    var uniqueTrackersCache: [String] = [allTrackersToken]

    // MARK: - UI & Loading State
    var isFilteringTasks = false
    var shouldHintOverlayLoadingForCurrentFilterPass = false
    var isOverlayLoadingVisible = false
    var hasAttemptedInitialLoad = false
    var showingAddMagnet = false
    var selectedTorrentForAction: TorrentTask?


    // MARK: - Side Effects
    @ObservationIgnored
    private var taskLookupByID: [String: TorrentTask] = [:]

    @ObservationIgnored
    private var rowStateByID: [String: TransfersRowState] = [:]

    @ObservationIgnored
    private var visibleTaskIDs = Set<String>()

    @ObservationIgnored
    private var currentAliasMap: [String: String] = [:]

    @ObservationIgnored
    private var currentDisplayOptions = TransfersRowDisplayOptions(
        isProUser: false,
        hideTracker: false,
        serverTypeByID: [:]
    )

    @ObservationIgnored
    private var searchDebounceTask: Task<Void, Never>?

    @ObservationIgnored
    private var filterComputationTask: Task<Void, Never>?

    @ObservationIgnored
    private var filterOptionsComputationTask: Task<Void, Never>?

    @ObservationIgnored
    private var overlayLoadingDelayTask: Task<Void, Never>?

    @ObservationIgnored
    private var deferredRefreshTask: Task<Void, Never>?

    @ObservationIgnored
    private var isUserScrolling = false

    @ObservationIgnored
    private var hasDeferredRefreshWhileScrolling = false

    @ObservationIgnored
    private var deferredRefreshShowOverlayHint = false

    /// Stashed filter result computed while the user was scrolling.
    /// Applied immediately after scroll ends to avoid racing with deceleration animation.
    @ObservationIgnored
    private var pendingFilteredContent: FilteredContentResult?

    // MARK: - Constants
    static let allCategoriesToken = "__ALL_CATEGORIES__"
    static let allTagsToken = "__ALL_TAGS__"
    static let allTrackersToken = "__ALL_TRACKERS__"

    // MARK: - Computed Properties
    var filteredTaskCount: Int {
        filteredTaskIDs.count
    }

    func uniqueCategories(isTransfersTabActive: Bool) -> [String] {
        guard isTransfersTabActive else { return [Self.allCategoriesToken] }
        return uniqueCategoriesCache
    }

    func uniqueTags(isTransfersTabActive: Bool) -> [String] {
        guard isTransfersTabActive else { return [Self.allTagsToken] }
        return uniqueTagsCache
    }

    func uniqueTrackers(isTransfersTabActive: Bool) -> [String] {
        guard isTransfersTabActive else { return [Self.allTrackersToken] }
        return uniqueTrackersCache
    }

    // MARK: - Interaction

    func toggleSelection(for taskID: String) {
        if selectedTaskHashes.contains(taskID) {
            selectedTaskHashes.remove(taskID)
        } else {
            selectedTaskHashes.insert(taskID)
        }
    }

    func selectAllFilteredTasks() {
        selectedTaskHashes = Set(filteredTaskIDs)
    }

    func clearFilteredSelection() {
        selectedTaskHashes.removeAll()
    }

    func task(for taskID: String) -> TorrentTask? {
        taskLookupByID[taskID]
    }

    func handleTransfersViewAppear(
        appStateManager: AppStateManager,
        isTransfersTabActive: Bool,
        displayOptions: TransfersRowDisplayOptions
    ) {
        debouncedSearchText = searchText
        scheduleFilteredTasksRecompute(
            isTransfersTabActive: isTransfersTabActive,
            appStateManager: appStateManager,
            displayOptions: displayOptions
        )
        scheduleFilterOptionsRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
        syncOverlayLoadingVisibility(isTransfersTabActive: isTransfersTabActive)
    }

    func handleSelectedTabChanged(
        _ newValue: AppTab,
        appStateManager: AppStateManager,
        displayOptions: TransfersRowDisplayOptions
    ) {
        scheduleFilteredTasksRecompute(
            showOverlayHint: newValue == .transfers,
            isTransfersTabActive: newValue == .transfers,
            appStateManager: appStateManager,
            displayOptions: displayOptions
        )
        scheduleFilterOptionsRecompute(isTransfersTabActive: newValue == .transfers, appStateManager: appStateManager)
        syncOverlayLoadingVisibility(isTransfersTabActive: newValue == .transfers)
    }

    func handleTransfersViewDisappear() {
        searchDebounceTask?.cancel()
        filterComputationTask?.cancel()
        filterOptionsComputationTask?.cancel()
        overlayLoadingDelayTask?.cancel()
        deferredRefreshTask?.cancel()
        isFilteringTasks = false
        shouldHintOverlayLoadingForCurrentFilterPass = false
        isOverlayLoadingVisible = false
        isUserScrolling = false
        hasDeferredRefreshWhileScrolling = false
        deferredRefreshShowOverlayHint = false
        pendingFilteredContent = nil
        filteredTaskIDs = []
        rowStateByID.removeAll()
        taskLookupByID.removeAll()
        visibleTaskIDs.removeAll()
    }

    func handleScrollActivityChanged(
        _ isScrolling: Bool,
        isTransfersTabActive: Bool,
        appStateManager: AppStateManager,
        displayOptions: TransfersRowDisplayOptions
    ) {
        guard isUserScrolling != isScrolling else { return }
        isUserScrolling = isScrolling
        appStateManager.setRefreshSuspension(isScrolling, source: Self.scrollRefreshSource)
        TransfersPosterDiagnostics.log(
            "scroll state changed isScrolling=\(isScrolling) deferred=\(hasDeferredRefreshWhileScrolling) rows=\(filteredTaskIDs.count)"
        )

        guard !isScrolling else { return }

        // Prefer applying a pre-computed result over launching a fresh recompute cycle.
        if let pending = pendingFilteredContent {
            pendingFilteredContent = nil
            hasDeferredRefreshWhileScrolling = false
            deferredRefreshShowOverlayHint = false
            TransfersPosterDiagnostics.log(
                "scroll settled apply pending result rows=\(pending.taskIDs.count)"
            )
            deferredRefreshTask?.cancel()
            deferredRefreshTask = Task { @MainActor [weak self] in
                // 150ms gap: let the final deceleration frame commit before we mutate state.
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled, let self else { return }
                self.applyFilteredContent(pending)
                self.isFilteringTasks = false
            }
            return
        }

        guard hasDeferredRefreshWhileScrolling else { return }

        let showOverlayHint = deferredRefreshShowOverlayHint
        hasDeferredRefreshWhileScrolling = false
        deferredRefreshShowOverlayHint = false
        TransfersPosterDiagnostics.log(
            "scroll settled trigger deferred recompute rows=\(filteredTaskIDs.count) showOverlayHint=\(showOverlayHint)"
        )
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduleFilteredTasksRecompute(
                showOverlayHint: showOverlayHint,
                isTransfersTabActive: isTransfersTabActive,
                appStateManager: appStateManager,
                displayOptions: displayOptions
            )
        }
    }

    func scheduleSearchDebounce() {
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
                self.debouncedSearchText = nextValue
            }
        }
    }

    func scheduleFilteredTasksRecompute(
        showOverlayHint: Bool = false,
        allowDeferralDuringScrolling: Bool = false,
        isTransfersTabActive: Bool,
        appStateManager: AppStateManager,
        displayOptions: TransfersRowDisplayOptions
    ) {
        if allowDeferralDuringScrolling && isUserScrolling {
            hasDeferredRefreshWhileScrolling = true
            deferredRefreshShowOverlayHint = deferredRefreshShowOverlayHint || showOverlayHint
            return
        }

        filterComputationTask?.cancel()

        let sourceTasks = isTransfersTabActive ? appStateManager.displayedTasks : []
        let statuses = selectedStatuses
        let categories = selectedCategories
        let tags = selectedTags
        let search = debouncedSearchText
        let trackers = selectedTrackers
        let sort = sortOption
        let ascending = sortAscending
        let categoryFilterSupported = appStateManager.activeServerType != .transmission
        let aliasMapSnapshot = displayOptions.isProUser ? TrackerAliasManager.shared.aliasMap : [:]
        let startUptime = DispatchTime.now().uptimeNanoseconds
        let computationPriority: TaskPriority = showOverlayHint ? .userInitiated : .utility



        shouldHintOverlayLoadingForCurrentFilterPass = showOverlayHint
        if isFilteringTasks != showOverlayHint {
            isFilteringTasks = showOverlayHint
        }

        filterComputationTask = Task {
            let computed = await Task.detached(priority: computationPriority) {
                Self.computeFilteredContent(
                    sourceTasks: sourceTasks,
                    selectedStatuses: statuses,
                    selectedCategories: categories,
                    selectedTags: tags,
                    searchText: search,
                    selectedTrackers: trackers,
                    isCategoryFilterSupported: categoryFilterSupported,
                    sortOption: sort,
                    sortAscending: ascending,
                    aliasMap: aliasMapSnapshot,
                    displayOptions: displayOptions
                )
            }.value

            guard !Task.isCancelled else { return }

            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
            let elapsedText = String(format: "%.1f", elapsedMs)
#if DEBUG
            if sourceTasks.count >= 50_000 {
                print("Transfers filter pass: source=\(sourceTasks.count) result=\(computed.taskIDs.count) elapsedMs=\(elapsedText)")
            }
#endif

            await MainActor.run {
                self.currentAliasMap = aliasMapSnapshot
                self.currentDisplayOptions = displayOptions
                if self.isUserScrolling {
                    // Defer apply until scroll ends to avoid contending with deceleration animation.
                    self.pendingFilteredContent = computed
                } else {
                    self.applyFilteredContent(computed)
                }
                if self.isFilteringTasks {
                    self.isFilteringTasks = false
                }
                if self.shouldHintOverlayLoadingForCurrentFilterPass {
                    self.shouldHintOverlayLoadingForCurrentFilterPass = false
                }
            }
        }
    }

    func syncOverlayLoadingVisibility(isTransfersTabActive: Bool) {
        overlayLoadingDelayTask?.cancel()

        let shouldRequest = isTransfersTabActive
            && !filteredTaskIDs.isEmpty
            && !shouldHintOverlayLoadingForCurrentFilterPass
            && isFilteringTasks

        guard shouldRequest else {
            isOverlayLoadingVisible = false
            return
        }

        guard !isOverlayLoadingVisible else { return }

        overlayLoadingDelayTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let currentShouldRequest = isTransfersTabActive
                    && !self.filteredTaskIDs.isEmpty
                    && !self.shouldHintOverlayLoadingForCurrentFilterPass
                    && self.isFilteringTasks
                if currentShouldRequest {
                    self.isOverlayLoadingVisible = true
                }
            }
        }
    }

    func rowState(for taskID: String) -> TransfersRowState {
        if let existing = rowStateByID[taskID] {
            return existing
        }

        let initialSnapshot = makeRowSnapshot(for: taskID) ?? TransfersRowDisplayModel(
            id: taskID,
            status: .paused,
            progress: 0,
            trackerText: nil,
            taxonomyTags: [],
            hiddenTaxonomyCount: 0,
            titleText: "",
            percentText: "",
            downloadSpeedText: "",
            uploadSpeedText: "",
            peersText: "",
            seedsText: "",
            sizeText: "",
            ratioText: "",
            seedingTimeText: "",
            savePathText: "",
            serverType: nil,
            resolutionBadge: nil,
            taskHash: "",
            taskRawName: "",
            preferredRowHeight: TransfersRowDisplayModel.defaultPreferredRowHeight
        )
        let state = TransfersRowState(snapshot: initialSnapshot)
        rowStateByID[taskID] = state
        return state
    }

    func preferredRowHeight(for taskID: String) -> CGFloat {
        if let state = rowStateByID[taskID] {
            return state.snapshot.preferredRowHeight
        }

        return makeRowSnapshot(for: taskID)?.preferredRowHeight
            ?? TransfersRowDisplayModel.defaultPreferredRowHeight
    }

    func setRowVisibility(_ taskID: String, isVisible: Bool) {
        if isVisible {
            visibleTaskIDs.insert(taskID)
            if let snapshot = makeRowSnapshot(for: taskID) {
                rowState(for: taskID).apply(snapshot)
            }
        } else {
            visibleTaskIDs.remove(taskID)
        }
    }

    private func applyFilteredContent(_ computed: FilteredContentResult) {
        taskLookupByID = computed.tasksByID
        if filteredTaskIDs != computed.taskIDs {
            filteredTaskIDs = computed.taskIDs
        }

        rowStateByID = rowStateByID.filter { computed.tasksByID[$0.key] != nil }
        visibleTaskIDs = visibleTaskIDs.filter { computed.tasksByID[$0] != nil }
        refreshVisibleRowStates()

        if !selectedTaskHashes.isEmpty {
            selectedTaskHashes = Set(selectedTaskHashes.filter { computed.tasksByID[$0] != nil })
        }
    }

    private func refreshVisibleRowStates(using precomputedSnapshots: [String: TransfersRowDisplayModel]? = nil) {
        guard !visibleTaskIDs.isEmpty else { return }
        let ids = Array(visibleTaskIDs)
        let batchSize = 3

        Task { @MainActor [weak self] in
            guard let self else { return }
            for startIndex in stride(from: 0, to: ids.count, by: batchSize) {
                let end = min(startIndex + batchSize, ids.count)
                for i in startIndex..<end {
                    let taskID = ids[i]
                    let snapshot: TransfersRowDisplayModel?
                    if let precomputed = precomputedSnapshots {
                        snapshot = precomputed[taskID]
                    } else {
                        snapshot = self.makeRowSnapshot(for: taskID)
                    }
                    guard let snapshot else { continue }
                    self.rowStateByID[taskID]?.apply(snapshot)
                }
                if end < ids.count {
                    await Task.yield()
                }
            }
        }
    }

    private func makeRowSnapshot(for taskID: String) -> TransfersRowDisplayModel? {
        guard let task = taskLookupByID[taskID] else { return nil }
        return TransfersRowDisplayModel.make(
            from: task,
            aliasMap: currentAliasMap,
            options: currentDisplayOptions
        )
    }

    func scheduleFilterOptionsRecompute(isTransfersTabActive: Bool, appStateManager: AppStateManager) {
        filterOptionsComputationTask?.cancel()

        guard isTransfersTabActive else {
            uniqueCategoriesCache = [Self.allCategoriesToken]
            uniqueTagsCache = [Self.allTagsToken]
            uniqueTrackersCache = [Self.allTrackersToken]
            return
        }

        let sourceTasks = appStateManager.displayedTasks
        let isCategoryFilterSupported = appStateManager.activeServerType != .transmission

        filterOptionsComputationTask = Task {
            let computed = await Self.computeFilterOptionsOnBackground(
                sourceTasks: sourceTasks,
                allCategoriesToken: Self.allCategoriesToken,
                allTagsToken: Self.allTagsToken,
                allTrackersToken: Self.allTrackersToken
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if self.uniqueCategoriesCache != computed.categories {
                    self.uniqueCategoriesCache = computed.categories
                }
                if self.uniqueTagsCache != computed.tags {
                    self.uniqueTagsCache = computed.tags
                }
                if self.uniqueTrackersCache != computed.trackers {
                    self.uniqueTrackersCache = computed.trackers
                }

                if !isCategoryFilterSupported {
                    self.selectedCategories.removeAll()
                } else {
                    let categoryOptions = Set(computed.categories.dropFirst())
                    self.selectedCategories = Set(self.selectedCategories.filter(categoryOptions.contains))
                }

                let tagOptions = Set(computed.tags.dropFirst())
                let trackerOptions = Set(computed.trackers.dropFirst())
                self.selectedTags = Set(self.selectedTags.filter(tagOptions.contains))
                self.selectedTrackers = Set(self.selectedTrackers.filter(trackerOptions.contains))
            }
        }
    }



    // MARK: - Static Computations

    nonisolated private static func computeFilteredContent(
        sourceTasks: [TorrentTask],
        selectedStatuses: Set<TaskStatusFilter>,
        selectedCategories: Set<String>,
        selectedTags: Set<String>,
        searchText: String,
        selectedTrackers: Set<String>,
        isCategoryFilterSupported: Bool,
        sortOption: SortOption,
        sortAscending: Bool,
        aliasMap: [String: String],
        displayOptions: TransfersRowDisplayOptions
    ) -> FilteredContentResult {
        guard !sourceTasks.isEmpty else {
            return FilteredContentResult(taskIDs: [], tasksByID: [:])
        }

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
            if Task.isCancelled {
                return FilteredContentResult(taskIDs: [], tasksByID: [:])
            }

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
                if task.name.lowercased().contains(normalizedSearch) || trackerHostLower.contains(normalizedSearch) {
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

        if Task.isCancelled {
            return FilteredContentResult(taskIDs: [], tasksByID: [:])
        }

        sortTasks(&filtered, by: sortOption, ascending: sortAscending)

        var taskIDs: [String] = []
        var tasksByID: [String: TorrentTask] = [:]
        taskIDs.reserveCapacity(filtered.count)
        tasksByID.reserveCapacity(filtered.count)

        for task in filtered {
            if Task.isCancelled {
                return FilteredContentResult(taskIDs: [], tasksByID: [:])
            }

            taskIDs.append(task.id)
            tasksByID[task.id] = task
        }

        return FilteredContentResult(
            taskIDs: taskIDs,
            tasksByID: tasksByID
        )
    }

    nonisolated private static func sortTasks(
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

    nonisolated private static func splitTags(_ rawTags: String) -> [String] {
        rawTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func containsAnyTag(_ rawTags: String, normalizedTags: Set<String>) -> Bool {
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

    private struct FilteredContentResult: Sendable {
        let taskIDs: [String]
        let tasksByID: [String: TorrentTask]
    }

    private struct TaskFilterOptions: Sendable {
        let categories: [String]
        let tags: [String]
        let trackers: [String]
    }

    nonisolated private static func computeFilterOptionsOnBackground(
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

    nonisolated private static func computeFilterOptions(
        sourceTasks: [TorrentTask],
        allCategoriesToken: String,
        allTagsToken: String,
        allTrackersToken: String
    ) -> TaskFilterOptions {
        var categories = Set<String>()
        var tags = Set<String>()
        var trackers = Set<String>()
        categories.reserveCapacity(min(sourceTasks.count, 2_048))
        tags.reserveCapacity(min(sourceTasks.count, 4_096))
        trackers.reserveCapacity(min(sourceTasks.count, 4_096))

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
}
