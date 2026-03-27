import SwiftUI

struct MoviePilotSectionListView: View {
    @State private var viewModel: MoviePilotSectionListViewModel
    @Namespace private var heroTransition

    init(bootstrap: MoviePilotSectionListBootstrapState) {
        _viewModel = State(wrappedValue: MoviePilotSectionListViewModel(bootstrap: bootstrap))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.viewState.items.isEmpty {
                    if viewModel.viewState.isInitialLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ContentUnavailableView(
                            "暂无内容",
                            systemImage: "film",
                            description: Text("稍后重试或下拉刷新。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    MoviePilotSectionPosterGridView(items: viewModel.viewState.items)
                        .equatable()

                    if viewModel.viewState.canLoadMore || viewModel.viewState.isLoadingMore {
                        MoviePilotSectionListLoadMoreView(isLoading: viewModel.viewState.isLoadingMore)
                            .id(viewModel.viewState.paginationTrigger)
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded()
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MoviePilotSectionListMediaDestination.self) { destination in
            MediaDetailView(
                initialViewState: viewModel.makeMediaDetailBootstrapViewState(for: destination.mediaID)
            )
            .navigationTransition(.zoom(sourceID: destination.mediaID, in: heroTransition))
        }
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }
}
