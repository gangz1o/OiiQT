//
//  TaskFilesView.swift
//  SeedPilot
//

import SwiftUI
import Observation

// MARK: - ViewModel

@MainActor @Observable
final class TaskFilesViewModel {
    let task: TorrentTask
    let appStateManager: AppStateManager

    var files: [TorrentFile] = []
    var isLoading = false
    var errorMessage: String?
    var selectedIndices: Set<Int> = []
    var isSelecting = false

    init(task: TorrentTask, appStateManager: AppStateManager) {
        self.task = task
        self.appStateManager = appStateManager
    }

    func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await appStateManager.fetchFiles(for: task)
            files = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        do {
            let fetched = try await appStateManager.fetchFiles(for: task)
            files = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPriority(_ priority: FilePriority, for indices: [Int]) {
        for i in files.indices where indices.contains(files[i].index) {
            files[i].priority = priority
        }

        Task {
            do {
                try await appStateManager.setFilePriority(for: task, fileIndices: indices, priority: priority)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
                await refresh()
            }
        }
    }

    func setSelectedPriority(_ priority: FilePriority) {
        let indices = Array(selectedIndices)
        guard !indices.isEmpty else { return }
        setPriority(priority, for: indices)
        selectedIndices.removeAll()
        isSelecting = false
    }

    func toggleSelection(for index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }

    func selectAll() {
        selectedIndices = Set(files.map(\.index))
    }

    func deselectAll() {
        selectedIndices.removeAll()
    }
}

// MARK: - View

struct TaskFilesView: View {
    @State private var viewModel: TaskFilesViewModel
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    init(task: TorrentTask, appStateManager: AppStateManager) {
        _viewModel = State(wrappedValue: TaskFilesViewModel(task: task, appStateManager: appStateManager))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.files.isEmpty {
                    ProgressView(languageManager.localized("Loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button(languageManager.localized("Retry")) {
                            Task { await viewModel.loadFiles() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    fileList
                }
            }
            .navigationTitle(languageManager.localized("Files"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isSelecting {
                        Menu {
                            priorityMenuItems { priority in
                                viewModel.setSelectedPriority(priority)
                            }
                        } label: {
                            Text(languageManager.localized("Set Priority"))
                                .font(.callout.weight(.medium))
                        }
                        .disabled(viewModel.selectedIndices.isEmpty)
                    } else {
                        Button(languageManager.localized("Select")) {
                            viewModel.isSelecting = true
                        }
                        .disabled(viewModel.files.isEmpty)
                    }
                }

                if viewModel.isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button(viewModel.selectedIndices.count == viewModel.files.count
                                   ? languageManager.localized("Deselect All")
                                   : languageManager.localized("Select All")) {
                                if viewModel.selectedIndices.count == viewModel.files.count {
                                    viewModel.deselectAll()
                                } else {
                                    viewModel.selectAll()
                                }
                            }

                            Spacer()

                            Text(String(format: languageManager.localized("Selected %d"), viewModel.selectedIndices.count))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(languageManager.localized("Cancel")) {
                                viewModel.isSelecting = false
                                viewModel.deselectAll()
                            }
                        }
                    }
                }
            }
            .task {
                await viewModel.loadFiles()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var fileList: some View {
        List {
            ForEach(viewModel.files) { file in
                fileRow(file)
                    .contextMenu {
                        priorityMenuItems { priority in
                            viewModel.setPriority(priority, for: [file.index])
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            viewModel.setPriority(.doNotDownload, for: [file.index])
                        } label: {
                            Label(languageManager.localized("Do Not Download"), systemImage: "nosign")
                        }
                        .tint(.gray)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            viewModel.setPriority(.maximum, for: [file.index])
                        } label: {
                            Label(languageManager.localized("Maximum"), systemImage: "flame.fill")
                        }
                        .tint(.red)

                        Button {
                            viewModel.setPriority(.high, for: [file.index])
                        } label: {
                            Label(languageManager.localized("High"), systemImage: "arrow.down.circle.fill")
                        }
                        .tint(.orange)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func fileRow(_ file: TorrentFile) -> some View {
        HStack(spacing: 12) {
            if viewModel.isSelecting {
                Image(systemName: viewModel.selectedIndices.contains(file.index) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedIndices.contains(file.index) ? .blue : .secondary)
                    .font(.title3)
                    .onTapGesture {
                        viewModel.toggleSelection(for: file.index)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(FormatHelper.displayTitle(from: file.name))
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(file.priority == .doNotDownload ? .secondary : .primary)

                ProgressView(value: file.progress, total: 1.0)
                    .tint(file.priority == .doNotDownload ? .gray : progressTint(file.progress))

                Text(file.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: file.priority.systemImage)
                    .font(.callout)
                    .foregroundStyle(file.priority.tintColor)

                Text(file.priority.localizedName)
                    .font(.caption2)
                    .foregroundStyle(file.priority.tintColor)
            }
            .frame(minWidth: 44)
        }
        .padding(.vertical, 4)
        .opacity(file.priority == .doNotDownload ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func priorityMenuItems(action: @escaping (FilePriority) -> Void) -> some View {
        ForEach(FilePriority.allCases, id: \.self) { priority in
            Button {
                action(priority)
            } label: {
                Label(priority.localizedName, systemImage: priority.systemImage)
            }
        }
    }

    private func progressTint(_ progress: Double) -> Color {
        if progress >= 1.0 { return .green }
        if progress >= 0.5 { return .blue }
        return .orange
    }
}
