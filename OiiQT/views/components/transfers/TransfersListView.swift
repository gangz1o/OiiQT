import SwiftUI
import UIKit

struct TransfersListView: View {
    let taskIDs: [String]
    let posterStore: TransfersPosterStore
    let selectedTaskIDs: Set<String>
    let isEditing: Bool
    let isOverlayLoadingVisible: Bool
    let showTMDBData: Bool
    var rowStateProvider: (String) -> TransfersRowState
    var rowHeightProvider: (String) -> CGFloat
    var onRowVisibilityChanged: (String, Bool) -> Void
    var onRefresh: () async -> Void
    var onScrollActivityChanged: (Bool) -> Void
    var onToggleSelection: (String) -> Void
    var onShowActionSheet: (String) -> Void
    var onDelete: (String) -> Void
    var onResume: (String) -> Void
    var onPause: (String) -> Void
    var onOpenDetail: (String) -> Void

    var body: some View {
        TransfersTableViewRepresentable(
            taskIDs: taskIDs,
            posterStore: posterStore,
            selectedTaskIDs: selectedTaskIDs,
            isEditing: isEditing,
            showTMDBData: showTMDBData,
            rowStateProvider: rowStateProvider,
            rowHeightProvider: rowHeightProvider,
            onRowVisibilityChanged: onRowVisibilityChanged,
            onRefresh: onRefresh,
            onScrollActivityChanged: onScrollActivityChanged,
            onToggleSelection: onToggleSelection,
            onShowActionSheet: onShowActionSheet,
            onDelete: onDelete,
            onResume: onResume,
            onPause: onPause,
            onOpenDetail: onOpenDetail
        )
        .overlay(alignment: .top) {
            tasksInlineLoadingOverlay
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
}

private struct TransfersTableViewRepresentable: UIViewRepresentable {
    let taskIDs: [String]
    let posterStore: TransfersPosterStore
    let selectedTaskIDs: Set<String>
    let isEditing: Bool
    let showTMDBData: Bool
    var rowStateProvider: (String) -> TransfersRowState
    var rowHeightProvider: (String) -> CGFloat
    var onRowVisibilityChanged: (String, Bool) -> Void
    var onRefresh: () async -> Void
    var onScrollActivityChanged: (Bool) -> Void
    var onToggleSelection: (String) -> Void
    var onShowActionSheet: (String) -> Void
    var onDelete: (String) -> Void
    var onResume: (String) -> Void
    var onPause: (String) -> Void
    var onOpenDetail: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellReuseIdentifier)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = true
        tableView.rowHeight = TransfersRowDisplayModel.defaultPreferredRowHeight
        tableView.estimatedRowHeight = TransfersRowDisplayModel.defaultPreferredRowHeight
        tableView.contentInset = .zero
        tableView.scrollIndicatorInsets = .zero
        tableView.keyboardDismissMode = .onDrag

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleRefresh),
            for: .valueChanged
        )
        tableView.refreshControl = refreshControl

        context.coordinator.attach(tableView: tableView)
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.update(parent: self, tableView: tableView)
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        static let cellReuseIdentifier = "TransfersTableCell"

        private var parent: TransfersTableViewRepresentable
        private weak var tableView: UITableView?
        private var isScrollActive = false

        init(parent: TransfersTableViewRepresentable) {
            self.parent = parent
        }

        func attach(tableView: UITableView) {
            self.tableView = tableView
        }

        func update(parent: TransfersTableViewRepresentable, tableView: UITableView) {
            let previousTaskIDs = self.parent.taskIDs
            let previousSelection = self.parent.selectedTaskIDs
            let previousEditing = self.parent.isEditing
            let previousShowPoster = self.parent.showTMDBData

            self.parent = parent
            self.tableView = tableView

            if previousTaskIDs != parent.taskIDs {
                // Diff-based update: reorder is cheap, structural change uses reloadData
                let oldSet = Set(previousTaskIDs)
                let newSet = Set(parent.taskIDs)

                if oldSet == newSet {
                    // Same items, just reordered → lightweight visible row reconfigure
                    reloadVisibleRows(on: tableView)
                } else {
                    tableView.reloadData()
                }
                return
            }

            if previousShowPoster != parent.showTMDBData {
                // Poster column changes every row's height. reloadData() clears the entire
                // UITableView height cache so off-screen rows are not measured at the old
                // size, which would cause scroll-offset corrections (micro-bounce) when
                // the user scrolls to them after the toggle.
                tableView.reloadData()
                return
            }

            if previousSelection != parent.selectedTaskIDs || previousEditing != parent.isEditing {
                reloadVisibleRows(on: tableView)
            }
        }

        @objc
        func handleRefresh() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.parent.onRefresh()
                self.tableView?.refreshControl?.endRefreshing()
            }
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            1
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.taskIDs.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
            configure(cell, at: indexPath)
            return cell
        }

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            preferredHeight(for: indexPath)
        }

        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            preferredHeight(for: indexPath)
        }

        func tableView(
            _ tableView: UITableView,
            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard !parent.isEditing else { return nil }
            guard let row = rowSnapshot(at: indexPath) else { return nil }

            if row.status == .paused {
                let resume = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
                    self?.parent.onResume(row.id)
                    completion(true)
                }
                resume.backgroundColor = .systemGreen
                resume.image = swipeActionImage(systemName: "play.fill")
                let configuration = UISwipeActionsConfiguration(actions: [resume])
                configuration.performsFirstActionWithFullSwipe = true
                return configuration
            }

            let pause = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
                self?.parent.onPause(row.id)
                completion(true)
            }
            pause.backgroundColor = .systemOrange
            pause.image = swipeActionImage(systemName: "pause.fill")
            let configuration = UISwipeActionsConfiguration(actions: [pause])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard !parent.isEditing else { return nil }
            guard let row = rowSnapshot(at: indexPath) else { return nil }

            let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
                self?.parent.onDelete(row.id)
                completion(true)
            }
            delete.image = swipeActionImage(systemName: "trash.fill")
            let configuration = UISwipeActionsConfiguration(actions: [delete])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard !isScrollActive else { return }
            isScrollActive = true
            parent.onScrollActivityChanged(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, isScrollActive else { return }
            isScrollActive = false
            parent.onScrollActivityChanged(false)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard isScrollActive else { return }
            isScrollActive = false
            parent.onScrollActivityChanged(false)
        }

        private func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
            guard indexPath.row < parent.taskIDs.count else { return }
            let taskID = parent.taskIDs[indexPath.row]
            let rowState = parent.rowStateProvider(taskID)

            cell.selectionStyle = .none
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.separatorInset = .zero
            cell.contentConfiguration = UIHostingConfiguration {
                TransfersHostedRowContent(
                    rowState: rowState,
                    posterStore: parent.posterStore,
                    selectedTaskIDs: parent.selectedTaskIDs,
                    isEditing: parent.isEditing,
                    showTMDBData: parent.showTMDBData,
                    onRowVisibilityChanged: parent.onRowVisibilityChanged,
                    onToggleSelection: parent.onToggleSelection,
                    onShowActionSheet: parent.onShowActionSheet,
                    onOpenDetail: parent.onOpenDetail
                )
            }
            .margins(.all, 0)
        }

        private func reloadVisibleRows(on tableView: UITableView) {
            guard let visible = tableView.indexPathsForVisibleRows, !visible.isEmpty else { return }
            for indexPath in visible {
                guard let cell = tableView.cellForRow(at: indexPath) else { continue }
                configure(cell, at: indexPath)
            }
        }

        private func rowSnapshot(at indexPath: IndexPath) -> TransfersRowDisplayModel? {
            guard indexPath.row < parent.taskIDs.count else { return nil }
            return parent.rowStateProvider(parent.taskIDs[indexPath.row]).snapshot
        }

        private func preferredHeight(for indexPath: IndexPath) -> CGFloat {
            guard indexPath.row < parent.taskIDs.count else {
                return TransfersRowDisplayModel.defaultPreferredRowHeight
            }
            let taskID = parent.taskIDs[indexPath.row]
            return parent.rowHeightProvider(taskID)
        }

        private func swipeActionImage(systemName: String) -> UIImage? {
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            return UIImage(systemName: systemName, withConfiguration: configuration)
        }
    }
}

private struct TransfersHostedRowContent: View {
    let rowState: TransfersRowState
    let posterStore: TransfersPosterStore
    let selectedTaskIDs: Set<String>
    let isEditing: Bool
    let showTMDBData: Bool
    var onRowVisibilityChanged: (String, Bool) -> Void
    var onToggleSelection: (String) -> Void
    var onShowActionSheet: (String) -> Void
    var onOpenDetail: (String) -> Void

    var body: some View {
        let row = rowState.snapshot

        TorrentRowView(
            row: row,
            posterState: posterStore.posterState(for: row.taskHash),
            showPoster: showTMDBData,
            isSelected: selectedTaskIDs.contains(row.id),
            isEditing: isEditing,
            toggleSelection: {
                onToggleSelection(row.id)
            },
            onShowActionSheet: {
                onShowActionSheet(row.id)
            }
        )
        .padding(.top, 4)
        .padding(.bottom, 4)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .onTapGesture {
            guard !isEditing else { return }
            onOpenDetail(row.id)
        }
        .onAppear {
            onRowVisibilityChanged(row.id, true)
            guard showTMDBData else { return }
            posterStore.resolveIfNeeded(for: row.taskHash, name: row.taskRawName)
        }
        .onDisappear {
            onRowVisibilityChanged(row.id, false)
        }
        .onChange(of: showTMDBData) { _, newValue in
            guard newValue else { return }
            posterStore.resolveIfNeeded(for: row.taskHash, name: row.taskRawName)
        }
    }
}
