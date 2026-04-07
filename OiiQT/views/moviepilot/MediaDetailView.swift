import SwiftUI
import UIKit

struct MediaDetailView: View {
    @Environment(AppStateManager.self) private var appStateManager
    @State private var viewModel: MediaDetailViewModel

    init(initialViewState: MediaDetailViewState) {
        _viewModel = State(wrappedValue: MediaDetailViewModel(initialViewState: initialViewState))
    }

    var body: some View {
        MediaDetailPageContentView(
            viewState: viewModel.pageViewState,
            onSearch: { viewModel.intentSearch() },
            onPresentSearchFilters: { viewModel.presentSearchFilterSheet() },
            onTapSearchResult: { resultID in
                Task {
                    await viewModel.prepareDownloadForm(for: resultID)
                }
            }
        )
        .navigationTitle(moviePilotLocalized(viewModel.pageViewState.navigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: viewModel.pageViewState.id) {
            await viewModel.loadDetail(id: viewModel.pageViewState.id)
        }
        .task {
            viewModel.configure(taskRefreshCoordinator: appStateManager)
        }
        .sheet(item: searchFilterSheetBinding) { sheetViewState in
            SearchResultFilterSheetView(
                viewState: viewModel.searchFilterSheetViewState ?? sheetViewState,
                onSelectSite: { viewModel.updateSearchFilterSite($0) },
                onSelectResolution: { viewModel.updateSearchFilterResolution($0) },
                onSelectQuality: { viewModel.updateSearchFilterQuality($0) },
                onSelectCodec: { viewModel.updateSearchFilterCodec($0) },
                onTogglePromotionOnly: { viewModel.updateSearchFilterPromotionOnly($0) },
                onToggleHideHitAndRun: { viewModel.updateSearchFilterHideHitAndRun($0) },
                onSelectSortField: { viewModel.updateSearchFilterSortField($0) },
                onSelectSortOrder: { viewModel.updateSearchFilterSortOrder($0) },
                onReset: { viewModel.resetSearchFilterSheet() },
                onCancel: { viewModel.cancelSearchFilterSheet() },
                onApply: { viewModel.applySearchFilterSheet() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: downloadFormBinding) { _ in
            if let form = viewModel.downloadFormViewState {
                DownloadConfigurationSheetView(
                    viewState: form,
                    onSelectDownloader: { viewModel.updateDownloadFormDownloader($0) },
                    onUpdateSavePath: { viewModel.updateDownloadFormSavePath($0) },
                    onCancel: { viewModel.cancelDownload() },
                    onConfirm: { await viewModel.confirmDownload() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage = viewModel.viewState.toastMessage {
                Text(toastMessage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.viewState.toastMessage)
        .task(id: viewModel.viewState.toastMessage) {
            guard viewModel.viewState.toastMessage != nil else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                viewModel.clearToastMessage()
            }
        }
    }

    private var searchFilterSheetBinding: Binding<SearchResultFilterSheetViewState?> {
        Binding(
            get: { viewModel.searchFilterSheetViewState },
            set: { newValue in
                guard newValue == nil else { return }
                viewModel.applySearchFilterSheet()
            }
        )
    }

    private var downloadFormBinding: Binding<DownloadFormViewState?> {
        Binding(
            get: { viewModel.downloadFormViewState },
            set: { newValue in
                if newValue == nil {
                    viewModel.cancelDownload()
                }
            }
        )
    }
}
