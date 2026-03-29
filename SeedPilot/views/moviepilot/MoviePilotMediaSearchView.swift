import SwiftUI

struct MoviePilotMediaSearchView: View {
    @State private var viewModel: MoviePilotMediaSearchViewModel

    init(bootstrap: MoviePilotMediaSearchBootstrapState) {
        _viewModel = State(wrappedValue: MoviePilotMediaSearchViewModel(bootstrap: bootstrap))
    }

    var body: some View {
        List {
            if viewModel.viewState.items.isEmpty {
                searchEmptyState
                    .moviePilotListRowInsets(top: 24, bottom: 32)
            } else {
                ForEach(viewModel.viewState.items) { item in
                    NavigationLink(value: MoviePilotSectionListMediaDestination(mediaID: item.id)) {
                        MoviePilotSectionListRowView(viewState: item)
                    }
                    .buttonStyle(.plain)
                    .moviePilotListRowInsets(top: 0, bottom: 0)
                }

                if viewModel.viewState.canLoadMore || viewModel.viewState.isLoadingMore {
                    MoviePilotSectionListLoadMoreView(isLoading: viewModel.viewState.isLoadingMore)
                        .id(viewModel.viewState.paginationTrigger)
                        .moviePilotListRowInsets(top: 12, bottom: 24)
                        .onAppear {
                            Task {
                                await viewModel.loadNextPageIfNeeded()
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .defersAppRefreshWhileScrolling("moviePilot.search")
        .navigationTitle(moviePilotLocalized(viewModel.viewState.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(moviePilotLocalized(viewModel.viewState.title))
                        .font(.headline)
                    Text(viewModel.viewState.query)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationDestination(for: MoviePilotSectionListMediaDestination.self) { destination in
            MediaDetailView(
                initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: destination.mediaID)
            )
        }
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        if viewModel.viewState.isInitialLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = viewModel.viewState.errorMessage, !errorMessage.isEmpty {
            ContentUnavailableView(
                moviePilotLocalized("搜索失败"),
                systemImage: "wifi.exclamationmark",
                description: Text(moviePilotLocalized(errorMessage))
            )
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView.search(text: viewModel.viewState.query)
                .frame(maxWidth: .infinity)
        }
    }
}
