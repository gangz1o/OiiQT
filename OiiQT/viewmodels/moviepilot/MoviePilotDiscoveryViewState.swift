import Foundation

nonisolated struct MediaCardViewState: Identifiable, Equatable, Sendable {
    let id: String
    let posterURLString: String
    let posterURL: URL?
    let title: String
    let ratingText: String
    let isSeries: Bool
    let mediaTypeText: String
    let accessibilityLabel: String
    let year: String
    let overview: String
    let castNames: [String]

    init(
        id: String,
        posterURLString: String,
        title: String,
        ratingText: String,
        isSeries: Bool,
        mediaTypeText: String? = nil,
        accessibilityLabel: String? = nil,
        year: String = "",
        overview: String = "",
        castNames: [String] = []
    ) {
        self.id = id
        self.posterURLString = posterURLString
        self.posterURL = URL(string: posterURLString)
        self.title = title
        self.ratingText = ratingText
        self.isSeries = isSeries
        self.year = year
        self.overview = overview
        self.castNames = castNames

        let resolvedMediaTypeText = mediaTypeText ?? (isSeries ? "剧集" : "电影")
        self.mediaTypeText = resolvedMediaTypeText

        if let accessibilityLabel {
            self.accessibilityLabel = accessibilityLabel
        } else if ratingText.isEmpty {
            self.accessibilityLabel = "\(title)，\(resolvedMediaTypeText)"
        } else {
            self.accessibilityLabel = "\(title)，\(resolvedMediaTypeText)，评分 \(ratingText)"
        }
    }
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
