nonisolated struct MediaCardViewState: Identifiable, Equatable, Sendable {
    let id: String
    let posterURLString: String
    let title: String
    let ratingText: String
    let isSeries: Bool
}

nonisolated struct MediaSectionViewState: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let cards: [MediaCardViewState]
}

nonisolated struct DiscoveryPageViewState: Identifiable, Equatable, Sendable {
    let id: String
    let categoryTabs: [String]
    let selectedCategory: String
    let sections: [MediaSectionViewState]
}

nonisolated struct MoviePilotSectionListBootstrapState: Equatable, Sendable {
    let sectionID: String
    let title: String
    let route: MoviePilotDiscoveryRoute
    let baseURLString: String
    let token: String
    let initialCards: [MediaCardViewState]
}

nonisolated struct MoviePilotSectionListViewState: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let items: [MediaCardViewState]
    let isInitialLoading: Bool
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let paginationTrigger: Int
}

nonisolated struct MoviePilotDiscoverySectionDestination: Hashable, Sendable {
    let sectionID: String
}

nonisolated struct MoviePilotMediaSearchDestination: Hashable, Sendable {
    let query: String
}

nonisolated struct MoviePilotMediaSearchBootstrapState: Equatable, Sendable {
    let query: String
    let baseURLString: String
    let token: String
}

nonisolated struct MoviePilotMediaSearchViewState: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let query: String
    let items: [MediaCardViewState]
    let isInitialLoading: Bool
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let paginationTrigger: Int
    let errorMessage: String?
}

nonisolated struct MoviePilotSectionListMediaDestination: Hashable, Sendable {
    let mediaID: String
}
