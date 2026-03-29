import Foundation
import Observation

@MainActor
@Observable
final class MoviePilotDiscoveryViewModel {
    nonisolated private static let pageID = "moviepilot.discovery.page"
    nonisolated private static let allCategory = "全部"
    nonisolated private static let movieCategory = "电影"
    nonisolated private static let tvCategory = "电视剧"
    nonisolated private static let animationCategory = "动漫"
    nonisolated private static let categoryTabs = [
        allCategory,
        movieCategory,
        tvCategory,
        animationCategory
    ]
    nonisolated private static let tmdbPosterBaseURLString = "https://image.tmdb.org/t/p/w500"
    nonisolated private static let sectionDescriptors: [MoviePilotDiscoverySectionDescriptor] = [
        MoviePilotDiscoverySectionDescriptor(
            id: "section-bangumi-calendar",
            title: "Bangumi 每日放送",
            category: animationCategory,
            route: .bangumiCalendar()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-showing",
            title: "豆瓣正在热映",
            category: movieCategory,
            route: .doubanShowing()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-movies",
            title: "豆瓣电影",
            category: movieCategory,
            route: .doubanMovies()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-tvs",
            title: "豆瓣剧集",
            category: tvCategory,
            route: .doubanTVs()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-movie-top250",
            title: "豆瓣电影 TOP250",
            category: movieCategory,
            route: .doubanMovieTop250()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-tv-weekly-chinese",
            title: "豆瓣国产剧集周榜",
            category: tvCategory,
            route: .doubanTVWeeklyChinese()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-tv-weekly-global",
            title: "豆瓣全球剧集周榜",
            category: tvCategory,
            route: .doubanTVWeeklyGlobal()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-tv-animation",
            title: "豆瓣动画剧集",
            category: animationCategory,
            route: .doubanTVAnimation()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-movie-hot",
            title: "豆瓣热门电影",
            category: movieCategory,
            route: .doubanMovieHot()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-douban-tv-hot",
            title: "豆瓣热门剧集",
            category: tvCategory,
            route: .doubanTVHot()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-tmdb-movies",
            title: "TMDB 电影",
            category: movieCategory,
            route: .tmdbMovies()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-tmdb-tvs",
            title: "TMDB 剧集",
            category: tvCategory,
            route: .tmdbTVs()
        ),
        MoviePilotDiscoverySectionDescriptor(
            id: "section-tmdb-trending",
            title: "TMDB 流行趋势",
            category: allCategory,
            route: .tmdbTrending()
        )
    ]

    @ObservationIgnored
    private let serverStore: MoviePilotServerStore

    @ObservationIgnored
    private let apiClient: MoviePilotDiscoveryAPIClient

    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            rebuildViewState()
        }
    }

    private(set) var viewState: DiscoveryPageViewState

    private var selectedCategory = MoviePilotDiscoveryViewModel.allCategory {
        didSet {
            guard oldValue != selectedCategory else { return }
            rebuildViewState()
        }
    }

    private var sectionSeeds: [MoviePilotDiscoverySectionSeed]
    private var isLoadingDiscoveryData = false

    convenience init() {
        self.init(
            serverStore: .shared,
            apiClient: .shared,
            sectionSeeds: []
        )
    }

    init(
        serverStore: MoviePilotServerStore,
        apiClient: MoviePilotDiscoveryAPIClient,
        sectionSeeds: [MoviePilotDiscoverySectionSeed]
    ) {
        self.serverStore = serverStore
        self.apiClient = apiClient
        self.sectionSeeds = sectionSeeds
        self.viewState = DiscoveryPageViewState(
            id: MoviePilotDiscoveryViewModel.pageID,
            categoryTabs: MoviePilotDiscoveryViewModel.categoryTabs,
            selectedCategory: MoviePilotDiscoveryViewModel.allCategory,
            sections: []
        )
        rebuildViewState()
    }

    func selectCategory(_ category: String) {
        guard MoviePilotDiscoveryViewModel.categoryTabs.contains(category) else { return }
        selectedCategory = category
    }

    func makeMediaDetailBootstrapViewState(for mediaID: String) -> MediaDetailViewState {
        guard let card = sectionSeeds.lazy
            .flatMap(\.cards)
            .first(where: { $0.id == mediaID }) else {
            return .placeholder(id: mediaID)
        }

        return .bootstrap(from: card)
    }

    func makeSectionListBootstrapState(for sectionID: String) -> MoviePilotSectionListBootstrapState? {
        guard let requestContext = availableServerContext(),
              let descriptor = Self.sectionDescriptors.first(where: { $0.id == sectionID }),
              let seed = sectionSeeds.first(where: { $0.id == sectionID }) else {
            return nil
        }

        return MoviePilotSectionListBootstrapState(
            sectionID: descriptor.id,
            title: descriptor.title,
            route: descriptor.route,
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            initialCards: seed.cards
        )
    }

    func makeMediaSearchDestination() -> MoviePilotMediaSearchDestination? {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        return MoviePilotMediaSearchDestination(query: trimmedQuery)
    }

    func makeMediaSearchBootstrapState(for query: String) -> MoviePilotMediaSearchBootstrapState? {
        guard let requestContext = availableServerContext() else {
            return nil
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        return MoviePilotMediaSearchBootstrapState(
            query: trimmedQuery,
            baseURLString: requestContext.baseURLString,
            token: requestContext.token
        )
    }

    func loadDiscoveryData() async {
        guard !isLoadingDiscoveryData else { return }
        isLoadingDiscoveryData = true
        defer { isLoadingDiscoveryData = false }

        guard let requestContext = availableServerContext() else {
            sectionSeeds = []
            rebuildViewState()
            return
        }

        let searchSnapshot = searchText
        let selectedCategorySnapshot = selectedCategory

        let fetchedSections = await Self.fetchAllSections(
            apiClient: apiClient,
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            descriptors: Self.sectionDescriptors
        )

        let tokenSnapshot = requestContext.token
        let payload = await Task.detached(priority: .userInitiated) {
            Self.makeDiscoveryPayload(
                baseURLString: requestContext.baseURLString,
                token: tokenSnapshot,
                searchText: searchSnapshot,
                selectedCategory: selectedCategorySnapshot,
                fetchedSections: fetchedSections
            )
        }.value

        apply(payload, searchSnapshot: searchSnapshot, selectedCategorySnapshot: selectedCategorySnapshot)
    }

    private func rebuildViewState() {
        let nextViewState = Self.makeDiscoveryPageViewState(
            sectionSeeds: sectionSeeds,
            searchText: searchText,
            selectedCategory: selectedCategory
        )

        if nextViewState != viewState {
            viewState = nextViewState
        }
    }

    private func availableServerContext() -> MoviePilotDiscoveryRequestContext? {
        guard let context = serverStore.activeServerContext else { return nil }
        return MoviePilotDiscoveryRequestContext(
            baseURLString: context.baseURLString,
            token: context.token
        )
    }

    private func apply(
        _ payload: MoviePilotDiscoveryPayload,
        searchSnapshot: String,
        selectedCategorySnapshot: String
    ) {
        sectionSeeds = payload.sectionSeeds

        if searchSnapshot == searchText && selectedCategorySnapshot == selectedCategory {
            viewState = payload.viewState
        } else {
            rebuildViewState()
        }
    }

    nonisolated private static func fetchAllSections(
        apiClient: MoviePilotDiscoveryAPIClient,
        baseURLString: String,
        token: String,
        descriptors: [MoviePilotDiscoverySectionDescriptor]
    ) async -> [MoviePilotDiscoveryFetchedSection] {
        let orderIndex = Dictionary(
            uniqueKeysWithValues: descriptors.enumerated().map { ($0.element.id, $0.offset) }
        )

        return await withTaskGroup(
            of: MoviePilotDiscoveryFetchedSection.self,
            returning: [MoviePilotDiscoveryFetchedSection].self
        ) { group in
            for descriptor in descriptors {
                group.addTask {
                    let dtos = await fetchMediaSafely(
                        apiClient: apiClient,
                        baseURLString: baseURLString,
                        token: token,
                        route: descriptor.route
                    )
                    return MoviePilotDiscoveryFetchedSection(
                        descriptor: descriptor,
                        dtos: dtos
                    )
                }
            }

            var sections: [MoviePilotDiscoveryFetchedSection] = []
            for await section in group {
                sections.append(section)
            }

            return sections.sorted {
                (orderIndex[$0.descriptor.id] ?? .max) < (orderIndex[$1.descriptor.id] ?? .max)
            }
        }
    }

    nonisolated private static func fetchMediaSafely(
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
            print("MoviePilot discovery request failed for \(route.path): \(error.localizedDescription)")
            return []
        }
    }

    nonisolated private static func makeDiscoveryPayload(
        baseURLString: String,
        token: String,
        searchText: String,
        selectedCategory: String,
        fetchedSections: [MoviePilotDiscoveryFetchedSection]
    ) -> MoviePilotDiscoveryPayload {
        let sectionSeeds = makeSectionSeeds(
            baseURLString: baseURLString,
            token: token,
            fetchedSections: fetchedSections
        )

        let viewState = makeDiscoveryPageViewState(
            sectionSeeds: sectionSeeds,
            searchText: searchText,
            selectedCategory: selectedCategory
        )

        return MoviePilotDiscoveryPayload(
            sectionSeeds: sectionSeeds,
            viewState: viewState
        )
    }

    nonisolated private static func makeSectionSeeds(
        baseURLString: String,
        token: String,
        fetchedSections: [MoviePilotDiscoveryFetchedSection]
    ) -> [MoviePilotDiscoverySectionSeed] {
        fetchedSections.map { fetchedSection in
            makeSectionSeed(
                descriptor: fetchedSection.descriptor,
                dtos: fetchedSection.dtos,
                baseURLString: baseURLString,
                token: token
            )
        }
    }

    nonisolated private static func makeSectionSeed(
        descriptor: MoviePilotDiscoverySectionDescriptor,
        dtos: MPMediaListDTO,
        baseURLString: String,
        token: String
    ) -> MoviePilotDiscoverySectionSeed {
        MoviePilotDiscoverySectionSeed(
            id: descriptor.id,
            title: descriptor.title,
            category: descriptor.category,
            cards: dtos.enumerated().map { index, dto in
                MoviePilotMediaCardMapper.makeCardViewState(
                    sectionID: descriptor.id,
                    index: index,
                    dto: dto,
                    baseURLString: baseURLString,
                    token: token
                )
            }
        )
    }

    nonisolated private static func makeDiscoveryPageViewState(
        sectionSeeds: [MoviePilotDiscoverySectionSeed],
        searchText: String,
        selectedCategory: String
    ) -> DiscoveryPageViewState {
        _ = searchText

        let sections = sectionSeeds.compactMap { seed -> MediaSectionViewState? in
            let categoryFilteredCards = filterCards(
                seed.cards,
                for: selectedCategory,
                sectionCategory: seed.category
            )

            guard !categoryFilteredCards.isEmpty else {
                return nil
            }

            return MediaSectionViewState(
                id: seed.id,
                title: seed.title,
                cards: categoryFilteredCards
            )
        }

        return DiscoveryPageViewState(
            id: pageID,
            categoryTabs: categoryTabs,
            selectedCategory: selectedCategory,
            sections: sections
        )
    }

    nonisolated private static func filterCards(
        _ cards: [MediaCardViewState],
        for selectedCategory: String,
        sectionCategory: String
    ) -> [MediaCardViewState] {
        switch selectedCategory {
        case allCategory:
            return cards
        case movieCategory:
            if sectionCategory == movieCategory {
                return cards
            }
            if sectionCategory == allCategory {
                return cards.filter { !$0.isSeries }
            }
            return []
        case tvCategory:
            if sectionCategory == tvCategory {
                return cards
            }
            if sectionCategory == allCategory {
                return cards.filter(\.isSeries)
            }
            return []
        case animationCategory:
            return sectionCategory == animationCategory ? cards : []
        default:
            return cards
        }
    }

}

nonisolated enum MoviePilotMediaCardMapper {
    private static let tmdbPosterBaseURLString = "https://image.tmdb.org/t/p/w500"

    static func makeCardViewState(
        sectionID: String,
        index: Int,
        dto: MPMediaItemDTO,
        baseURLString: String,
        token _: String
    ) -> MediaCardViewState {
        let displayTitle = normalizedDisplayTitle(from: dto)
        let identifier = stableIdentifier(
            sectionID: sectionID,
            index: index,
            dto: dto,
            displayTitle: displayTitle
        )

        return MediaCardViewState(
            id: identifier,
            posterURLString: completedPosterURLString(from: dto, baseURLString: baseURLString),
            title: displayTitle,
            ratingText: normalizedRatingText(from: dto),
            isSeries: isSeries(from: dto),
            year: dto.year ?? dto.titleYear ?? "",
            overview: dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            castNames: dto.castNames
        )
    }

    private static func stableIdentifier(
        sectionID: String,
        index: Int,
        dto: MPMediaItemDTO,
        displayTitle: String
    ) -> String {
        if let mediaID = dto.mediaID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mediaID.isEmpty {
            if mediaID.contains(":") {
                return mediaID
            }

            let prefix = normalizedMediaIDPrefix(from: dto)
            if !prefix.isEmpty {
                return "\(prefix):\(mediaID)"
            }

            return mediaID
        }

        if let tmdbID = dto.tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let doubanID = dto.doubanID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !doubanID.isEmpty {
            return "douban:\(doubanID)"
        }

        if let bangumiID = dto.bangumiID {
            return "bangumi:\(bangumiID)"
        }

        if let imdbID = dto.imdbID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imdbID.isEmpty {
            return "imdb:\(imdbID)"
        }

        let normalizedTitle = displayTitle
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(sectionID)-\(index)-\(normalizedTitle)"
    }

    private static func normalizedMediaIDPrefix(from dto: MPMediaItemDTO) -> String {
        let candidates = [
            dto.mediaIDPrefix,
            dto.source
        ]

        for candidate in candidates {
            let trimmed = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return ""
    }

    private static func normalizedDisplayTitle(from dto: MPMediaItemDTO) -> String {
        let candidates = [
            dto.title,
            dto.name,
            dto.originalTitle,
            dto.originalName,
            dto.enTitle
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return moviePilotLocalized("未知标题")
    }

    private static func normalizedRatingText(from dto: MPMediaItemDTO) -> String {
        guard let ratingValue = ratingValue(from: dto), ratingValue > 0 else {
            return ""
        }
        return String(format: "%.1f", ratingValue)
    }

    private static func ratingValue(from dto: MPMediaItemDTO) -> Double? {
        if let voteAverage = dto.voteAverage, voteAverage > 0 {
            return voteAverage
        }

        if let ratingValue = dto.rating?.value, ratingValue > 0 {
            return ratingValue
        }

        return nil
    }

    private static func isSeries(from dto: MPMediaItemDTO) -> Bool {
        let normalizedType = dto.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let source = normalizedSource(from: dto)

        if source == "bangumi" {
            return true
        }

        if normalizedType.contains("tv")
            || normalizedType.contains("series")
            || normalizedType.contains("剧")
            || normalizedType.contains("anime")
            || normalizedType.contains("bangumi")
            || normalizedType.contains("动画") {
            return true
        }

        if normalizedType.contains("movie") || normalizedType.contains("电影") {
            return false
        }

        if dto.firstAirDate != nil || dto.originalName != nil {
            return true
        }

        return false
    }

    private static func completedPosterURLString(
        from dto: MPMediaItemDTO,
        baseURLString: String
    ) -> String {
        let rawPosterPath = (dto.posterPath ?? dto.backdropPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPosterPath.isEmpty else {
            return ""
        }

        let lowercasedPath = rawPosterPath.lowercased()
        let normalizedSource = normalizedSource(from: dto)
        let isTMDBSource = normalizedSource == "tmdb" || dto.tmdbID != nil
        let isDoubanSource = normalizedSource == "douban"
            || lowercasedPath.contains("doubanio.com")

        if lowercasedPath.hasPrefix("http://") || lowercasedPath.hasPrefix("https://") {
            if isDoubanSource {
                return normalizedDoubanImageURLString(rawPosterPath)
            }
            return rawPosterPath
        }

        if rawPosterPath.hasPrefix("/api/") {
            return makeMoviePilotAbsoluteURL(
                baseURLString: baseURLString,
                relativePath: rawPosterPath
            ) ?? rawPosterPath
        }

        if rawPosterPath.hasPrefix("/") {
            if isTMDBSource {
                return tmdbPosterBaseURLString + rawPosterPath
            }

            if isDoubanSource {
                return normalizedDoubanImageURLString(rawPosterPath)
            }

            return makeMoviePilotAbsoluteURL(
                baseURLString: baseURLString,
                relativePath: rawPosterPath
            ) ?? rawPosterPath
        }

        if isDoubanSource {
            return normalizedDoubanImageURLString(rawPosterPath)
        }

        return rawPosterPath
    }

    private static func normalizedDoubanImageURLString(_ rawPath: String) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return rawPath }

        let lowercasedPath = trimmedPath.lowercased()
        if lowercasedPath.hasPrefix("http://") || lowercasedPath.hasPrefix("https://") {
            return trimmedPath
        }

        if trimmedPath.hasPrefix("//") {
            return "https:\(trimmedPath)"
        }

        if lowercasedPath.contains("doubanio.com") {
            let normalizedPath = trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "https://\(normalizedPath)"
        }

        if trimmedPath.hasPrefix("/") {
            return "https://img9.doubanio.com\(trimmedPath)"
        }

        return "https://img9.doubanio.com/\(trimmedPath)"
    }

    private static func makeMoviePilotAbsoluteURL(
        baseURLString: String,
        relativePath: String
    ) -> String? {
        guard let normalizedBaseURL = MoviePilotURLNormalizer.normalize(baseURLString),
              let baseURL = URL(string: normalizedBaseURL),
              let absoluteURL = URL(string: relativePath, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        return absoluteURL.absoluteString
    }

    private static func normalizedSource(from dto: MPMediaItemDTO) -> String {
        let trimmedSource = dto.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if trimmedSource == "themoviedb" {
            return "tmdb"
        }

        return trimmedSource
    }
}

nonisolated struct MoviePilotDiscoveryRequestContext: Sendable, Equatable {
    let baseURLString: String
    let token: String
}

nonisolated struct MoviePilotDiscoverySectionDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String
    let route: MoviePilotDiscoveryRoute
}

nonisolated struct MoviePilotDiscoveryFetchedSection: Sendable, Equatable {
    let descriptor: MoviePilotDiscoverySectionDescriptor
    let dtos: MPMediaListDTO
}

nonisolated struct MoviePilotDiscoverySectionSeed: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String
    let cards: [MediaCardViewState]
}

nonisolated struct MoviePilotDiscoveryPayload: Sendable, Equatable {
    let sectionSeeds: [MoviePilotDiscoverySectionSeed]
    let viewState: DiscoveryPageViewState
}
