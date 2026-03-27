import SwiftUI

struct MediaDetailView: View {
    @State private var viewModel: MediaDetailViewModel

    init(initialViewState: MediaDetailViewState) {
        _viewModel = State(wrappedValue: MediaDetailViewModel(initialViewState: initialViewState))
    }

    var body: some View {
        MediaDetailPageContentView(
            viewState: viewModel.pageViewState,
            onSearch: { viewModel.intentSearch() },
            onSubscribe: { viewModel.intentSubscribe() },
            onPresentSearchFilters: { viewModel.presentSearchFilterSheet() },
            onTapSearchResult: { resultID in
                Task {
                    await viewModel.prepareDownloadForm(for: resultID)
                }
            }
        )
        .navigationTitle(viewModel.pageViewState.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: viewModel.pageViewState.id) {
            await viewModel.loadDetail(id: viewModel.pageViewState.id)
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
        .sheet(isPresented: subscribeSheetBinding) {
            if let form = viewModel.subscribeFormViewState {
                SubscribeSettingsSheetView(
                    viewState: form,
                    onSelectOption: { fieldID, optionID in
                        viewModel.updateSubscribeOption(fieldID: fieldID, optionID: optionID)
                    },
                    onUpdateText: { fieldID, text in
                        viewModel.updateSubscribeText(fieldID: fieldID, text: text)
                    },
                    onToggle: { fieldID, isOn in
                        viewModel.updateSubscribeToggle(fieldID: fieldID, isOn: isOn)
                    },
                    onCancel: {
                        viewModel.dismissSubscribeSheet()
                    },
                    onSubmit: {
                        await viewModel.submitSubscription(form: viewModel.subscribeFormViewState)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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

    private var subscribeSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showSubscribeSheet },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSubscribeSheet()
                }
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
