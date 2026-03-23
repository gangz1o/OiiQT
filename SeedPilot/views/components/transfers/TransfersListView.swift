import SwiftUI

struct TransfersListView: View {
    @Bindable var viewModel: TransfersViewModel
    var appStateManager: AppStateManager
    var isEditing: Bool
    
    var body: some View {
        List {
            ForEach(viewModel.filteredTasks) { task in
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
    
    private func taskRowCell(_ task: TorrentTask) -> some View {
        TorrentRowView(
            task: task,
            isSelected: viewModel.selectedTaskHashes.contains(task.id),
            isEditing: isEditing,
            toggleSelection: {
                viewModel.toggleSelection(for: task.id)
            },
            onShowActionSheet: { selectedTask, posterURL in
                viewModel.selectedTorrentPosterURL = posterURL
                viewModel.selectedTorrentForAction = selectedTask
            },
            appStateManager: appStateManager
        )
        .equatable()
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditing {
                Button {
                    appStateManager.deleteTask(task, withData: true)
                } label: {
                    Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
                }
                .tint(.red)
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
        if viewModel.isOverlayLoadingVisible {
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
}
