//
//  BatchActionPanel.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct BatchActionMenu: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Binding var selectedTaskHashes: Set<String>
    @Binding var isEditing: Bool

    @State private var showingBatchLocationAlert = false
    @State private var showingBatchPresetLocationPicker = false
    @State private var newBatchLocation = ""
    @State private var showingBatchTrackerAlert = false
    @State private var newBatchTrackers = ""
    @State private var showingBatchDeleteConfirmation = false
    @State private var showingCategoryUnsupportedAlert = false
    @State private var showingBatchCategorySelector = false
    @State private var showingBatchTagSelector = false
    @State private var batchSelectedCategory = ""
    @State private var batchSelectedTags: Set<String> = []
    @State private var actionErrorMessage = ""
    @State private var showingActionErrorAlert = false
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    private var selectedTasks: [TorrentTask] {
        appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
    }

    /// True when every visible task is selected — enables O(1) API path.
    private var isSelectAll: Bool {
        !selectedTaskHashes.isEmpty && selectedTaskHashes.count == appStateManager.allTasks.count
    }

    /// Raw torrent hashes for bulk APIs.
    private var batchHashes: [String] {
        Array(Set(selectedTasks.map(\.hash)))
    }

    /// Single-server scope (nil = multi-server).
    private var batchServerID: UUID? {
        let ids = Set(selectedTasks.map(\.serverID))
        return ids.count == 1 ? ids.first : nil
    }

    private var isMixedServerSelection: Bool {
        batchServerID == nil && selectedTasks.count > 0
    }

    private var areAllPaused: Bool {
        !selectedTasks.isEmpty && selectedTasks.allSatisfy { $0.status == .paused }
    }

    private var containsTransmissionSelection: Bool {
        selectedTasks.contains { task in
            appStateManager.servers.first(where: { $0.id == task.serverID })?.type == .transmission
        }
    }

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    private var batchCategoryOptions: [String] {
        appStateManager.availableCategoryOptions(for: selectedTasksSet)
    }

    private var batchTagOptions: [String] {
        appStateManager.availableTagOptions(for: selectedTasksSet)
    }

    var body: some View {
        Menu {
            if areAllPaused {
                Button {
                    performAction { appStateManager.resumeTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll) }
                } label: {
                    Label(LanguageManager.shared.localized("Resume"), systemImage: "play.fill")
                }
            } else {
                Button {
                    performAction { appStateManager.pauseTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll) }
                } label: {
                    Label(LanguageManager.shared.localized("Pause"), systemImage: "pause.fill")
                }
            }

            Button {
                performAction { appStateManager.forceStartTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll) }
            } label: {
                Label(LanguageManager.shared.localized("Force Resume"), systemImage: "forward.fill")
            }

            Button {
                performAction { appStateManager.recheckTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll) }
            } label: {
                Label(LanguageManager.shared.localized("Recheck"), systemImage: "checkmark.seal.fill")
            }

            Button {
                performAction { appStateManager.reannounceTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll) }
            } label: {
                Label(LanguageManager.shared.localized("Reannounce"), systemImage: "arrow.clockwise.circle.fill")
            }

            Button {
                showingBatchLocationAlert = true
            } label: {
                Label(LanguageManager.shared.localized("Change Location"), systemImage: "folder.badge.plus")
            }
            .disabled(isMixedServerSelection)

            Button {
                showingBatchTrackerAlert = true
            } label: {
                Label(LanguageManager.shared.localized("Edit Tracker"), systemImage: "link.badge.plus")
            }

            Button {
                handleBatchCategoryTapped()
            } label: {
                Label(LanguageManager.shared.localized("Category"), systemImage: "tray.full")
            }
            .opacity(containsTransmissionSelection ? 0.5 : 1)

            Button {
                handleBatchTagsTapped()
            } label: {
                Label(LanguageManager.shared.localized("Tags"), systemImage: "tag")
            }

            Button(role: .destructive) {
                showingBatchDeleteConfirmation = true
            } label: {
                Label(LanguageManager.shared.localized("Delete"), systemImage: "trash.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .disabled(selectedTasks.isEmpty)
        .onAppear {
            prewarmTaxonomy()
        }
        .onChange(of: selectedTaskHashes) { _, _ in
            prewarmTaxonomy()
        }
        .alert(LanguageManager.shared.localized("Batch Set Save Path"), isPresented: $showingBatchLocationAlert) {
            TextField(LanguageManager.shared.localized("New Path"), text: $newBatchLocation)
            Button(LanguageManager.shared.localized("Choose Preset Path")) {
                showingBatchPresetLocationPicker = true
            }
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                let trimmed = newBatchLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                guard !isMixedServerSelection else { return }
                performAction {
                    appStateManager.setTransferLocationBatch(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll, newLocation: trimmed)
                }
                newBatchLocation = ""
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter a new absolute path. This action will move data for selected tasks."))
        }
        .confirmationDialog(
            LanguageManager.shared.localized("Preset Save Paths"),
            isPresented: $showingBatchPresetLocationPicker,
            titleVisibility: .visible
        ) {
            if presetSavePaths.isEmpty {
                Button(LanguageManager.shared.localized("No Preset Save Paths")) {}
                    .disabled(true)
            } else {
                ForEach(presetSavePaths, id: \.self) { path in
                    Button(path) {
                        newBatchLocation = path
                        DispatchQueue.main.async {
                            showingBatchLocationAlert = true
                        }
                    }
                }
            }
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {}
        }
        .alert(LanguageManager.shared.localized("Edit Tracker"), isPresented: $showingBatchTrackerAlert) {
            TextField(LanguageManager.shared.localized("Tracker URL"), text: $newBatchTrackers)
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                performAction {
                    appStateManager.editTrackersBatch(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll, newTrackers: newBatchTrackers)
                }
                newBatchTrackers = ""
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter Tracker URL. For multiple URLs, try comma separation if supported by your server."))
        }
        .confirmationDialog(LanguageManager.shared.localized("Batch Delete"), isPresented: $showingBatchDeleteConfirmation, titleVisibility: .visible) {
            Button(LanguageManager.shared.localized("Delete Task (Keep Data)"), role: .destructive) {
                performAction {
                    appStateManager.deleteTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll, withData: false)
                }
            }
            Button(LanguageManager.shared.localized("Delete Task and Data"), role: .destructive) {
                performAction {
                    appStateManager.deleteTasks(hashes: batchHashes, serverID: batchServerID, isSelectAll: isSelectAll, withData: true)
                }
            }
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
        } message: {
            Text(
                String(
                    format: LanguageManager.shared.localized("Are you sure you want to delete %d selected tasks?"),
                    selectedTasks.count
                )
            )
        }
        .alert(LanguageManager.shared.localized("Feature Unavailable"), isPresented: $showingCategoryUnsupportedAlert) {
            Button(LanguageManager.shared.localized("OK"), role: .cancel) {}
        } message: {
            Text(LanguageManager.shared.localized("Transmission servers do not support category. Please select only qBittorrent tasks."))
        }
        .alert(LanguageManager.shared.localized("Error"), isPresented: $showingActionErrorAlert) {
            Button(LanguageManager.shared.localized("OK"), role: .cancel) {}
        } message: {
            Text(actionErrorMessage)
        }
        .sheet(isPresented: $showingBatchCategorySelector) {
            CategorySelectionSheetView(
                categories: batchCategoryOptions,
                initialSelection: batchSelectedCategory
            ) { category in
                Task {
                    await applyBatchCategory(category)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingBatchTagSelector) {
            TagMultiSelectSheetView(
                availableTags: batchTagOptions,
                initialSelection: batchSelectedTags
            ) { tags in
                Task {
                    await applyBatchTags(tags)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func performAction(action: () -> Void) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        action()

        withAnimation {
            isEditing = false
            selectedTaskHashes.removeAll()
        }
    }

    private func handleBatchCategoryTapped() {
        guard !containsTransmissionSelection else {
            showingCategoryUnsupportedAlert = true
            return
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        batchSelectedCategory = ""
        showingBatchCategorySelector = true
    }

    private func handleBatchTagsTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        batchSelectedTags = Set(selectedTasks.flatMap { parseTags($0.tags) })
        showingBatchTagSelector = true
    }

    private var selectedTasksSet: Set<TorrentTask> {
        Set(selectedTasks)
    }

    private func prewarmTaxonomy() {
        guard !selectedTasksSet.isEmpty else { return }
        appStateManager.prewarmTaxonomyIfNeeded(for: selectedTasksSet)
    }

    private func applyBatchCategory(_ category: String) async {
        do {
            try await appStateManager.applyCategory(category, to: selectedTasksSet)
            await MainActor.run {
                withAnimation {
                    isEditing = false
                    selectedTaskHashes.removeAll()
                }
            }
        } catch {
            await MainActor.run {
                actionErrorMessage = localizedErrorMessage(error)
                showingActionErrorAlert = true
            }
        }
    }

    private func applyBatchTags(_ tags: [String]) async {
        do {
            try await appStateManager.applyTags(tags, to: selectedTasksSet)
            await MainActor.run {
                withAnimation {
                    isEditing = false
                    selectedTaskHashes.removeAll()
                }
            }
        } catch {
            await MainActor.run {
                actionErrorMessage = localizedErrorMessage(error)
                showingActionErrorAlert = true
            }
        }
    }

    private func parseTags(_ raw: String) -> [String] {
        Array(
            Set(
                raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if case let TorrentClientError.apiError(message) = error {
            return LanguageManager.shared.localized(message)
        }
        return error.localizedDescription
    }
}
