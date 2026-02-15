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
    @State private var newBatchLocation = ""
    @State private var showingBatchTrackerAlert = false
    @State private var newBatchTrackers = ""
    @State private var showingBatchDeleteConfirmation = false

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

    var areAllPaused: Bool {
        !selectedTasks.isEmpty && selectedTasks.allSatisfy { $0.status == .paused }
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
                    ActionButton(icon: "play.fill", text: "继续") {
                        performAction { appStateManager.resumeTasks(Set(selectedTasks)) }
                    }
                } else {
                    ActionButton(icon: "pause.fill", text: "暂停") {
                        performAction { appStateManager.pauseTasks(Set(selectedTasks)) }
                    }
                }

                // 2. Force Resume
                ActionButton(icon: "forward.fill", text: "强制继续") {
                    performAction { appStateManager.forceStartTasks(Set(selectedTasks)) }
                }

                // 3. Recheck
                ActionButton(icon: "checkmark.seal.fill", text: "重新校验") {
                    performAction { appStateManager.recheckTasks(Set(selectedTasks)) }
                }

                // 4. Reannounce
                ActionButton(icon: "arrow.clockwise.circle.fill", text: "重新汇报") {
                    performAction { appStateManager.reannounceTasks(Set(selectedTasks)) }
                }

                // 5. Set Location
                ActionButton(icon: "folder.badge.plus", text: "更改位置") {
                    showingBatchLocationAlert = true
                }

                // 6. Edit Trackers
                ActionButton(icon: "link.badge.plus", text: "修改 Tracker") {
                    showingBatchTrackerAlert = true
                }

                // 7. Delete (Red)
                ActionButton(icon: "trash.fill", text: "删除", color: .red) {
                    showingBatchDeleteConfirmation = true
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30) // Safe area
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
        .alert("批量修改保存路径", isPresented: $showingBatchLocationAlert) {
            TextField("新路径", text: $newBatchLocation)
            Button("取消", role: .cancel) { }
            Button("确定") {
                performAction {
                    appStateManager.setTransferLocationBatch(Set(selectedTasks), newLocation: newBatchLocation)
                }
                newBatchLocation = ""
            }
        } message: {
            Text("请输入新的绝对路径。此操作将移动所选任务的数据。")
        }
        .alert("批量添加 Tracker", isPresented: $showingBatchTrackerAlert) {
            TextField("Tracker URL", text: $newBatchTrackers)
            Button("取消", role: .cancel) { }
            Button("确定") {
                performAction {
                    appStateManager.editTrackersBatch(Set(selectedTasks), newTrackers: newBatchTrackers)
                }
                newBatchTrackers = ""
            }
        } message: {
            Text("请输入 Tracker URL。")
        }
        .confirmationDialog("批量删除", isPresented: $showingBatchDeleteConfirmation, titleVisibility: .visible) {
            Button("删除任务 (保留数据)", role: .destructive) {
                performAction {
                    for task in selectedTasks {
                        appStateManager.deleteTask(task, withData: false)
                    }
                }
            }
            Button("删除任务和数据", role: .destructive) {
                performAction {
                    for task in selectedTasks {
                        appStateManager.deleteTask(task, withData: true)
                    }
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除选中的 \(selectedTasks.count) 个任务吗？")
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
    }
}
