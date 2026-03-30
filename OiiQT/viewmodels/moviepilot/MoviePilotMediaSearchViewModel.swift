import Foundation
import Observation

@MainActor
@Observable
final class MoviePilotMediaSearchViewModel {
    nonisolated private static let pageSize = 20

    @ObservationIgnored
    private let apiClient: MoviePilotDiscoveryAPIClient

    @ObservationIgnored
    private let bootstrap: MoviePilotMediaSearchBootstrapState

    private var loadedPage = 0
    private var knownMediaIDs: Set<String> = []
    private var isRequestInFlight = false

    private(set) var viewState: MoviePilotMediaSearchViewState

    init(
        bootstrap: MoviePilotMediaSearchBootstrapState,
        apiClient: MoviePilotDiscoveryAPIClient = .shared
    ) {
        self.apiClient = apiClient
        self.bootstrap = bootstrap
        self.viewState = MoviePilotMediaSearchViewState(
            id: "moviepilot.search.\(bootstrap.query)",
            title: "搜索结果",
            query: bootstrap.query,
            items: [],
            isInitialLoading: true,
            isLoadingMore: false,
            canLoadMore: true,
            paginationTrigger: 0,
            errorMessage: nil
        )
    }

    func makeMediaDetailBootstrapViewState(for mediaID: String) -> MediaDetailViewState {
        guard let card = viewState.items.first(where: { $0.id == mediaID }) else {
            return .placeholder(id: mediaID)
        }

        return .bootstrap(from: card)
    }

    func loadInitialPageIfNeeded() async {
        guard viewState.items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        guard !isRequestInFlight else { return }

        loadedPage = 0
        knownMediaIDs.removeAll(keepingCapacity: true)
        viewState = MoviePilotMediaSearchViewState(
            id: viewState.id,
            title: viewState.title,
            query: bootstrap.query,
            items: [],
            isInitialLoading: true,
            isLoadingMore: false,
            canLoadMore: true,
            paginationTrigger: 0,
            errorMessage: nil
        )

        await loadNextPageIfNeeded()
    }

    func loadNextPageIfNeeded() async {
        guard !isRequestInFlight, viewState.canLoadMore else {
            return
        }

        isRequestInFlight = true
        setLoadingState(isLoading: true)
        defer {
            isRequestInFlight = false
            setLoadingState(isLoading: false)
        }

        let nextPage = max(loadedPage + 1, 1)

        do {
            let dtos = try await apiClient.requestMediaSearchResults(
                baseURLString: bootstrap.baseURLString,
                token: bootstrap.token,
                title: bootstrap.query,
                page: nextPage,
                count: Self.pageSize
            )

            let pageOffset = max((nextPage - 1) * Self.pageSize, 0)
            let nextCards = dtos.enumerated().compactMap { index, dto -> MediaCardViewState? in
                let card = MoviePilotMediaCardMapper.makeCardViewState(
                    sectionID: viewState.id,
                    index: pageOffset + index,
                    dto: dto,
                    baseURLString: bootstrap.baseURLString,
                    token: bootstrap.token
                )

                guard knownMediaIDs.insert(card.id).inserted else {
                    return nil
                }
                return card
            }

            loadedPage = nextPage
            let items = nextPage == 1 ? nextCards : (viewState.items + nextCards)
            let canLoadMore = !dtos.isEmpty && dtos.count >= Self.pageSize

            viewState = MoviePilotMediaSearchViewState(
                id: viewState.id,
                title: viewState.title,
                query: bootstrap.query,
                items: items,
                isInitialLoading: false,
                isLoadingMore: false,
                canLoadMore: canLoadMore,
                paginationTrigger: loadedPage,
                errorMessage: nil
            )
        } catch {
            viewState = MoviePilotMediaSearchViewState(
                id: viewState.id,
                title: viewState.title,
                query: bootstrap.query,
                items: viewState.items,
                isInitialLoading: false,
                isLoadingMore: false,
                canLoadMore: false,
                paginationTrigger: viewState.paginationTrigger,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func setLoadingState(isLoading: Bool) {
        let isInitialLoading = isLoading && viewState.items.isEmpty
        let isLoadingMore = isLoading && !viewState.items.isEmpty

        if viewState.isInitialLoading == isInitialLoading && viewState.isLoadingMore == isLoadingMore {
            return
        }

        viewState = MoviePilotMediaSearchViewState(
            id: viewState.id,
            title: viewState.title,
            query: viewState.query,
            items: viewState.items,
            isInitialLoading: isInitialLoading,
            isLoadingMore: isLoadingMore,
            canLoadMore: viewState.canLoadMore,
            paginationTrigger: viewState.paginationTrigger,
            errorMessage: viewState.errorMessage
        )
    }
}
