//
//  BatchActionPanel.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct BatchActionPanel: View {
    @Environment(AppStateManager.self) private var appStateManager
    @Binding var selectedTaskHashes: Set<String>
    @Binding var isEditing: Bool

    // Alert States
    @State private var showingBatchLocationAlert = false
    @State private var showingBatchPresetLocationPicker = false
    @State private var newBatchLocation = ""
    @State private var showingBatchTrackerAlert = false
    @State private var newBatchTrackers = ""
    @State private var showingBatchDeleteConfirmation = false
    @State private var showingCategoryUnsupportedAlert = false
    @State private var showingBatchCategorySelector = false
    @State private var showingBatchTagSelector = false
    @State private var batchCategoryOptions: [String] = []
    @State private var batchTagOptions: [String] = []
    @State private var batchSelectedCategory = ""
    @State private var batchSelectedTags: Set<String> = []
    @State private var actionErrorMessage = ""
    @State private var showingActionErrorAlert = false
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    // Grid Setup
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var selectedTasks: [TorrentTask] {
        appStateManager.allTasks.filter { selectedTaskHashes.contains($0.id) }
    }

    var isMixedServerSelection: Bool {
        Set(selectedTasks.map(\.serverID)).count > 1
    }

    var areAllPaused: Bool {
        !selectedTasks.isEmpty && selectedTasks.allSatisfy { $0.status == .paused }
    }

    var containsTransmissionSelection: Bool {
        selectedTasks.contains { task in
            appStateManager.servers.first(where: { $0.id == task.serverID })?.type == .transmission
        }
    }

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Grid
            LazyVGrid(columns: columns, spacing: 20) {
                // 1. Resume / Pause
                if areAllPaused {
                    ActionButton(icon: "play.fill", text: LanguageManager.shared.localized("Resume")) {
                        performAction { appStateManager.resumeTasks(Set(selectedTasks)) }
                    }
                } else {
                    ActionButton(icon: "pause.fill", text: LanguageManager.shared.localized("Pause")) {
                        performAction { appStateManager.pauseTasks(Set(selectedTasks)) }
                    }
                }

                // 2. Force Resume
                ActionButton(icon: "forward.fill", text: LanguageManager.shared.localized("Force Resume")) {
                    performAction { appStateManager.forceStartTasks(Set(selectedTasks)) }
                }

                // 3. Recheck
                ActionButton(icon: "checkmark.seal.fill", text: LanguageManager.shared.localized("Recheck")) {
                    performAction { appStateManager.recheckTasks(Set(selectedTasks)) }
                }

                // 4. Reannounce
                ActionButton(icon: "arrow.clockwise.circle.fill", text: LanguageManager.shared.localized("Reannounce")) {
                    performAction { appStateManager.reannounceTasks(Set(selectedTasks)) }
                }

                // 5. Set Location
                ActionButton(
                    icon: "folder.badge.plus",
                    text: LanguageManager.shared.localized("Change Location"),
                    isDisabled: isMixedServerSelection
                ) {
                    showingBatchLocationAlert = true
                }

                // 6. Edit Trackers
                ActionButton(
                    icon: "link.badge.plus",
                    text: LanguageManager.shared.localized("Edit Tracker"),
                    isDisabled: selectedTasks.isEmpty
                ) {
                    showingBatchTrackerAlert = true
                }

                // 7. Category (qB only)
                ActionButton(
                    icon: "tray.full",
                    text: LanguageManager.shared.localized("Category")
                ) {
                    handleBatchCategoryTapped()
                }
                .opacity(containsTransmissionSelection ? 0.5 : 1)

                // 8. Tags
                ActionButton(
                    icon: "tag",
                    text: LanguageManager.shared.localized("Tags")
                ) {
                    handleBatchTagsTapped()
                }

                // 9. Delete (Red)
                ActionButton(icon: "trash.fill", text: LanguageManager.shared.localized("Delete"), color: .red) {
                    showingBatchDeleteConfirmation = true
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30) // Safe area
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
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
                    appStateManager.setTransferLocationBatch(Set(selectedTasks), newLocation: trimmed)
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
                        // Let users confirm explicitly in the main alert before sending the request.
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
                    appStateManager.editTrackersBatch(Set(selectedTasks), newTrackers: newBatchTrackers)
                }
                newBatchTrackers = ""
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter Tracker URL. For multiple URLs, try comma separation if supported by your server."))
        }
        .confirmationDialog(LanguageManager.shared.localized("Batch Delete"), isPresented: $showingBatchDeleteConfirmation, titleVisibility: .visible) {
            Button(LanguageManager.shared.localized("Delete Task (Keep Data)"), role: .destructive) {
                performAction {
                    appStateManager.deleteTasks(Set(selectedTasks), withData: false)
                }
            }
            Button(LanguageManager.shared.localized("Delete Task and Data"), role: .destructive) {
                performAction {
                    appStateManager.deleteTasks(Set(selectedTasks), withData: true)
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

        // Auto exit edit mode?
        // User requested: "Ensure these operations can accurately apply to the currently selected Set<String>."
        // User didn't explicitly say to exit edit mode, but usually batch actions do.
        // Keeping it consistent with previous behavior.
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
        Task {
            do {
                let options = try await appStateManager.fetchTaskCategoryOptions(for: selectedTasksSet)
                await MainActor.run {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    batchCategoryOptions = options
                    batchSelectedCategory = ""
                    showingBatchCategorySelector = true
                }
            } catch {
                await MainActor.run {
                    actionErrorMessage = localizedErrorMessage(error)
                    showingActionErrorAlert = true
                }
            }
        }
    }

    private func handleBatchTagsTapped() {
        Task {
            do {
                let options = try await appStateManager.fetchTaskTagOptions(for: selectedTasksSet)
                let current = Set(selectedTasks.flatMap { parseTags($0.tags) })
                await MainActor.run {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    batchSelectedTags = current
                    batchTagOptions = Array(Set(options).union(current))
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    showingBatchTagSelector = true
                }
            } catch {
                await MainActor.run {
                    actionErrorMessage = localizedErrorMessage(error)
                    showingActionErrorAlert = true
                }
            }
        }
    }

    private var selectedTasksSet: Set<TorrentTask> {
        Set(selectedTasks)
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

struct ActionButton: View {
    let icon: String
    let text: String
    var color: Color = .primary
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemGray6))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(color)
                }

                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
