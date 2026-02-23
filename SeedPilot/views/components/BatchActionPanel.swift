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
                    isDisabled: isMixedServerSelection
                ) {
                    showingBatchTrackerAlert = true
                }

                // 7. Delete (Red)
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
        .alert(LanguageManager.shared.localized("Batch Add Tracker"), isPresented: $showingBatchTrackerAlert) {
            TextField(LanguageManager.shared.localized("Tracker URL"), text: $newBatchTrackers)
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                guard !isMixedServerSelection else { return }
                performAction {
                    appStateManager.editTrackersBatch(Set(selectedTasks), newTrackers: newBatchTrackers)
                }
                newBatchTrackers = ""
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter Tracker URL."))
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
