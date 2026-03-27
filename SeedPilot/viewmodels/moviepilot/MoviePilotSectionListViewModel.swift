import Foundation
import Observation

@MainActor
@Observable
final class MoviePilotSectionListViewModel {
    @ObservationIgnored
    private let apiClient: MoviePilotDiscoveryAPIClient

    @ObservationIgnored
    private let bootstrap: MoviePilotSectionListBootstrapState

    private var loadedPage: Int
    private var knownMediaIDs: Set<String>
    private var isRequestInFlight = false

    private(set) var viewState: MoviePilotSectionListViewState

    init(
        bootstrap: MoviePilotSectionListBootstrapState,
        apiClient: MoviePilotDiscoveryAPIClient = .shared
    ) {
        self.apiClient = apiClient
        self.bootstrap = bootstrap
        let initialLoadedPage = bootstrap.initialCards.isEmpty ? 0 : bootstrap.route.page
        self.loadedPage = initialLoadedPage
        self.knownMediaIDs = Set(bootstrap.initialCards.map(\.id))

        let canLoadMore = bootstrap.route.supportsPagination
            && (bootstrap.initialCards.isEmpty || bootstrap.initialCards.count >= bootstrap.route.expectedPageSize)
        self.viewState = MoviePilotSectionListViewState(
            id: bootstrap.sectionID,
            title: bootstrap.title,
            items: bootstrap.initialCards,
            isInitialLoading: bootstrap.initialCards.isEmpty,
            isLoadingMore: false,
            canLoadMore: canLoadMore,
            paginationTrigger: initialLoadedPage
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
        viewState = MoviePilotSectionListViewState(
            id: bootstrap.sectionID,
            title: bootstrap.title,
            items: [],
            isInitialLoading: true,
            isLoadingMore: false,
            canLoadMore: bootstrap.route.supportsPagination,
            paginationTrigger: 0
        )

        await loadNextPageIfNeeded()
    }

    func loadNextPageIfNeeded() async {
        guard bootstrap.route.supportsPagination,
              viewState.canLoadMore,
              !isRequestInFlight else {
            return
        }

        isRequestInFlight = true
        setLoadingState(isLoading: true)
        defer {
            isRequestInFlight = false
            setLoadingState(isLoading: false)
        }

        let nextPage = max(loadedPage + 1, 1)
        let route = bootstrap.route.withPage(nextPage)
        let dtos = await Self.fetchMediaPage(
            apiClient: apiClient,
            baseURLString: bootstrap.baseURLString,
            token: bootstrap.token,
            route: route
        )

        let pageOffset = max((nextPage - 1) * max(route.expectedPageSize, 1), 0)
        let nextCards = dtos.enumerated().compactMap { index, dto -> MediaCardViewState? in
            let card = MoviePilotMediaCardMapper.makeCardViewState(
                sectionID: bootstrap.sectionID,
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
        let canLoadMore = !dtos.isEmpty && dtos.count >= route.expectedPageSize
        viewState = MoviePilotSectionListViewState(
            id: bootstrap.sectionID,
            title: bootstrap.title,
            items: items,
            isInitialLoading: false,
            isLoadingMore: false,
            canLoadMore: canLoadMore,
            paginationTrigger: loadedPage
        )
    }

    private func setLoadingState(isLoading: Bool) {
        let isInitialLoading = isLoading && viewState.items.isEmpty
        let isLoadingMore = isLoading && !viewState.items.isEmpty

        if viewState.isInitialLoading == isInitialLoading && viewState.isLoadingMore == isLoadingMore {
            return
        }

        viewState = MoviePilotSectionListViewState(
            id: viewState.id,
            title: viewState.title,
            items: viewState.items,
            isInitialLoading: isInitialLoading,
            isLoadingMore: isLoadingMore,
            canLoadMore: viewState.canLoadMore,
            paginationTrigger: viewState.paginationTrigger
        )
    }

    nonisolated private static func fetchMediaPage(
        apiClient: MoviePilotDiscoveryAPIClient,
        baseURLString: String,
        token: String,
        route: MoviePilotDiscoveryRoute
    ) async -> MPMediaListDTO {
        do {
            return try await apiClient.requestMediaList(
                baseURLString: baseURLString,
                token: token,
                route: route
            )
        } catch {
            print("MoviePilot section list request failed for \(route.path): \(error.localizedDescription)")
            return []
        }
    }
}
