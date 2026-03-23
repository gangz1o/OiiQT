import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class TransfersViewModel {
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
    
    // MARK: - Tasks Data
    var filteredTasks: [TorrentTask] = []
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
    var selectedTorrentPosterURL: URL?

    // MARK: - Tasks
    private var searchDebounceTask: Task<Void, Never>?
    private var filterComputationTask: Task<Void, Never>?
    private var filterOptionsComputationTask: Task<Void, Never>?
    private var overlayLoadingDelayTask: Task<Void, Never>?

    // MARK: - Constants
    static let allCategoriesToken = "__ALL_CATEGORIES__"
    static let allTagsToken = "__ALL_TAGS__"
    static let allTrackersToken = "__ALL_TRACKERS__"

    // MARK: - Computed Properties
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

    // MARK: - Methods

    func toggleSelection(for hash: String) {
        if selectedTaskHashes.contains(hash) {
            selectedTaskHashes.remove(hash)
        } else {
            selectedTaskHashes.insert(hash)
        }
    }

    func handleTransfersViewAppear(appStateManager: AppStateManager, isTransfersTabActive: Bool) {
        debouncedSearchText = searchText
        scheduleFilteredTasksRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
        scheduleFilterOptionsRecompute(isTransfersTabActive: isTransfersTabActive, appStateManager: appStateManager)
        syncOverlayLoadingVisibility(isTransfersTabActive: isTransfersTabActive)
    }

    func handleSelectedTabChanged(_ newValue: AppTab, appStateManager: AppStateManager) {
        scheduleFilteredTasksRecompute(showOverlayHint: newValue == .transfers, isTransfersTabActive: newValue == .transfers, appStateManager: appStateManager)
        scheduleFilterOptionsRecompute(isTransfersTabActive: newValue == .transfers, appStateManager: appStateManager)
        syncOverlayLoadingVisibility(isTransfersTabActive: newValue == .transfers)
    }

    func handleTransfersViewDisappear() {
        searchDebounceTask?.cancel()
        filterComputationTask?.cancel()
        filterOptionsComputationTask?.cancel()
        overlayLoadingDelayTask?.cancel()
        isFilteringTasks = false
        shouldHintOverlayLoadingForCurrentFilterPass = false
        isOverlayLoadingVisible = false
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

    func scheduleFilteredTasksRecompute(showOverlayHint: Bool = false, isTransfersTabActive: Bool, appStateManager: AppStateManager) {
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
        let aliasMapSnapshot = TrackerAliasManager.shared.aliasMap
        let startUptime = DispatchTime.now().uptimeNanoseconds

        shouldHintOverlayLoadingForCurrentFilterPass = showOverlayHint
        if isFilteringTasks != showOverlayHint {
            isFilteringTasks = showOverlayHint
        }

        filterComputationTask = Task {
            let computed = await Task.detached(priority: .userInitiated) {
                Self.computeFilteredTasks(
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
            }.value
            
            guard !Task.isCancelled else { return }
            
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
#if DEBUG
            if sourceTasks.count >= 50_000 {
                let elapsedText = String(format: "%.1f", elapsedMs)
                print("Transfers filter pass: source=\(sourceTasks.count) result=\(computed.count) elapsedMs=\(elapsedText)")
            }
#endif
            
            await MainActor.run {
                if !(computed.isEmpty && self.filteredTasks.isEmpty) {
                    self.filteredTasks = computed
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
        
        let shouldRequest = isTransfersTabActive && !filteredTasks.isEmpty && !shouldHintOverlayLoadingForCurrentFilterPass && isFilteringTasks

        guard shouldRequest else {
            isOverlayLoadingVisible = false
            return
        }

        guard !isOverlayLoadingVisible else { return }

        overlayLoadingDelayTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let currentShouldRequest = isTransfersTabActive && !self.filteredTasks.isEmpty && !self.shouldHintOverlayLoadingForCurrentFilterPass && self.isFilteringTasks
                if currentShouldRequest {
                    self.isOverlayLoadingVisible = true
                }
            }
        }
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
                self.uniqueCategoriesCache = computed.categories
                self.uniqueTagsCache = computed.tags
                self.uniqueTrackersCache = computed.trackers

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

    nonisolated private static func computeFilteredTasks(
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
            if Task.isCancelled { return [] }

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

        if Task.isCancelled { return [] }
        sortTasks(
            &filtered,
            by: sortOption,
            ascending: sortAscending
        )
        return filtered
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
}
