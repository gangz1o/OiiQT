import SwiftUI

struct TransfersListView: View {
    let rows: [TransfersRowDisplayModel]
    let selectedTaskIDs: Set<String>
    let isEditing: Bool
    let isOverlayLoadingVisible: Bool
    let showTMDBData: Bool
    var onRefresh: () async -> Void
    var onScrollActivityChanged: (Bool) -> Void
    var onToggleSelection: (String) -> Void
    var onShowActionSheet: (String) -> Void
    var onDelete: (String) -> Void
    var onResume: (String) -> Void
    var onPause: (String) -> Void
    var onOpenDetail: (String) -> Void

    var body: some View {
        List {
            ForEach(rows) { row in
                taskRowCell(row)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await onRefresh()
        }
        .onScrollPhaseChange { _, newPhase in
            TransfersPosterDiagnostics.log(
                "list scroll phase isScrolling=\(newPhase.isScrolling) rows=\(rows.count) showPoster=\(showTMDBData) editing=\(isEditing)"
            )
            onScrollActivityChanged(newPhase.isScrolling)
        }
        .overlay(alignment: .top) {
            tasksInlineLoadingOverlay
        }
    }

    private func taskRowCell(_ row: TransfersRowDisplayModel) -> some View {
        TorrentRowView(
            row: row,
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
        .equatable()
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditing {
                Button {
                    onDelete(row.id)
                } label: {
                    Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading) {
            if !isEditing {
                if row.status == .paused {
                    Button {
                        onResume(row.id)
                    } label: {
                        Label(LanguageManager.shared.localized("Resume"), systemImage: "play.fill")
                    }
                    .tint(.green)
                } else {
                    Button {
                        onPause(row.id)
                    } label: {
                        Label(LanguageManager.shared.localized("Pause"), systemImage: "pause.fill")
                    }
                    .tint(.orange)
                }
            }
        }
        .onTapGesture {
            guard !isEditing else { return }
            onOpenDetail(row.id)
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
