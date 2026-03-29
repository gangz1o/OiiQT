import Foundation

nonisolated struct ActorViewState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let characterName: String
    let profileURLString: String
    let profileURL: URL?
    let accessibilityLabel: String

    init(
        id: String,
        name: String,
        characterName: String,
        profileURLString: String,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.characterName = characterName
        self.profileURLString = profileURLString
        self.profileURL = URL(string: profileURLString)

        let resolvedCharacterName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let accessibilityLabel {
            self.accessibilityLabel = accessibilityLabel
        } else if resolvedCharacterName.isEmpty {
            self.accessibilityLabel = name
        } else {
            self.accessibilityLabel = "\(name)，饰演 \(resolvedCharacterName)"
        }
    }
}

nonisolated struct MediaDetailViewState: Identifiable, Equatable, Sendable {
    var id: String
    var posterURLString: String
    var backdropURLString: String
    var title: String
    var ratingText: String
    var isSeries: Bool
    var releaseText: String?
    var directorText: String?
    var castText: String?
    var genreText: String?
    var overviewText: String?
    var actors: [ActorViewState]
    var isOverviewLoading: Bool
    var isActorsLoading: Bool
    var searchResults: [SearchResultViewState]
    var isSearchLoading: Bool
    var searchFeedbackText: String?
    var toastMessage: String?

    static func bootstrap(from card: MediaCardViewState) -> MediaDetailViewState {
        MediaDetailViewState(
            id: card.id,
            posterURLString: card.posterURLString,
            backdropURLString: "",
            title: card.title,
            ratingText: card.ratingText,
            isSeries: card.isSeries,
            releaseText: nil,
            directorText: nil,
            castText: nil,
            genreText: nil,
            overviewText: nil,
            actors: [],
            isOverviewLoading: true,
            isActorsLoading: true,
            searchResults: [],
            isSearchLoading: false,
            searchFeedbackText: nil,
            toastMessage: nil
        )
    }

    static func placeholder(id: String) -> MediaDetailViewState {
        MediaDetailViewState(
            id: id,
            posterURLString: "",
            backdropURLString: "",
            title: "",
            ratingText: "",
            isSeries: false,
            releaseText: nil,
            directorText: nil,
            castText: nil,
            genreText: nil,
            overviewText: nil,
            actors: [],
            isOverviewLoading: true,
            isActorsLoading: true,
            searchResults: [],
            isSearchLoading: false,
            searchFeedbackText: nil,
            toastMessage: nil
        )
    }
}

nonisolated struct SearchResultBadgePaletteViewState: Equatable, Sendable {
    let foregroundHex: String
    let backgroundHex: String
}

nonisolated struct SearchResultBadgeViewState: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let palette: SearchResultBadgePaletteViewState
}

// MARK: - Download Form

nonisolated struct DownloadFormViewState: Identifiable, Equatable, Sendable {
    let id: String // matches SearchResultViewState.id
    let resourceTitle: String
    let presetSavePaths: [String]
    var downloaders: [DownloaderOptionViewState]
    var selectedDownloaderID: String?
    var savePath: String
    var isSubmitting: Bool
    var errorMessage: String?
}

nonisolated struct DownloaderOptionViewState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

nonisolated struct SearchResultViewState: Identifiable, Equatable, Sendable {
    let id: String
    let sortPriority: Int
    let siteName: String
    let seedersCount: Int
    let leechersCount: Int
    let title: String
    let subtitle: String
    let sizeInBytes: Int64
    let sizeString: String
    let publishTimestamp: TimeInterval?
    let timeString: String
    let promotionTag: String?
    let promotionPalette: SearchResultBadgePaletteViewState?
    let badges: [SearchResultBadgeViewState]
    let qualityTag: String?
    let resolutionTag: String?
    let codecTag: String?
    let isHitAndRun: Bool
    let pageURLString: String
    let pageURL: URL?
    let accessibilityLabel: String

    init(
        id: String,
        sortPriority: Int,
        siteName: String,
        seedersCount: Int,
        leechersCount: Int,
        title: String,
        subtitle: String,
        sizeInBytes: Int64,
        sizeString: String,
        publishTimestamp: TimeInterval?,
        timeString: String,
        promotionTag: String?,
        promotionPalette: SearchResultBadgePaletteViewState?,
        badges: [SearchResultBadgeViewState],
        qualityTag: String?,
        resolutionTag: String?,
        codecTag: String?,
        isHitAndRun: Bool,
        pageURLString: String,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.sortPriority = sortPriority
        self.siteName = siteName
        self.seedersCount = seedersCount
        self.leechersCount = leechersCount
        self.title = title
        self.subtitle = subtitle
        self.sizeInBytes = sizeInBytes
        self.sizeString = sizeString
        self.publishTimestamp = publishTimestamp
        self.timeString = timeString
        self.promotionTag = promotionTag
        self.promotionPalette = promotionPalette
        self.badges = badges
        self.qualityTag = qualityTag
        self.resolutionTag = resolutionTag
        self.codecTag = codecTag
        self.isHitAndRun = isHitAndRun
        self.pageURLString = pageURLString
        self.pageURL = URL(string: pageURLString)

        if let accessibilityLabel {
            self.accessibilityLabel = accessibilityLabel
        } else {
            var components = [
                siteName,
                "做种 \(seedersCount)",
                title,
                subtitle,
                sizeString
            ]

            if let promotionTag {
                components.append("促销 \(promotionTag)")
            }

            if !badges.isEmpty {
                components.append(badges.map(\.text).joined(separator: "、"))
            }

            self.accessibilityLabel = components
                .filter { !$0.isEmpty }
                .joined(separator: "，")
        }
    }
}

nonisolated struct MediaDetailMetadataRowViewState: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let systemImage: String
    let lineLimit: Int
}

nonisolated struct MediaDetailHeroSectionViewState: Equatable, Sendable {
    let backgroundPosterURL: URL?
    let posterURL: URL?
    let title: String
    let mediaTypeText: String
    let ratingText: String
    let metadataRows: [MediaDetailMetadataRowViewState]
    let overviewText: String?
    let isOverviewLoading: Bool
    let showsSyncProgress: Bool
    let isSearchLoading: Bool
}

nonisolated struct MediaDetailActorsSectionViewState: Equatable, Sendable {
    let isLoading: Bool
    let actors: [ActorViewState]
}

nonisolated enum MediaDetailSearchSectionContentViewState: Equatable, Sendable {
    case hidden
    case loading
    case empty
    case filteredEmpty
    case results([SearchResultViewState])
}

nonisolated struct MediaDetailSearchSectionViewState: Equatable, Sendable {
    let feedbackText: String?
    let activeFilterCount: Int
    let showsFilterButton: Bool
    let content: MediaDetailSearchSectionContentViewState
}

nonisolated struct MediaDetailPageViewState: Identifiable, Equatable, Sendable {
    let id: String
    let navigationTitle: String
    let hero: MediaDetailHeroSectionViewState
    let actors: MediaDetailActorsSectionViewState
    let search: MediaDetailSearchSectionViewState
}

nonisolated enum SearchResultSortField: String, CaseIterable, Identifiable, Equatable, Sendable {
    case relevance
    case seeders
    case publishTime
    case size
    case site

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "默认"
        case .seeders: "做种数"
        case .publishTime: "发布时间"
        case .size: "文件大小"
        case .site: "站点"
        }
    }
}

nonisolated enum SearchResultSortOrder: String, CaseIterable, Identifiable, Equatable, Sendable {
    case descending
    case ascending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .descending: "降序"
        case .ascending: "升序"
        }
    }
}

nonisolated struct SearchResultFilterState: Equatable, Sendable {
    var selectedSiteName: String?
    var selectedResolution: String?
    var selectedQuality: String?
    var selectedCodec: String?
    var showPromotionOnly: Bool
    var hideHitAndRun: Bool
    var sortField: SearchResultSortField
    var sortOrder: SearchResultSortOrder

    static let `default` = SearchResultFilterState(
        selectedSiteName: nil,
        selectedResolution: nil,
        selectedQuality: nil,
        selectedCodec: nil,
        showPromotionOnly: false,
        hideHitAndRun: false,
        sortField: .relevance,
        sortOrder: .descending
    )
}

nonisolated struct SearchResultFilterOptionViewState: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

nonisolated struct SearchResultFilterSheetViewState: Identifiable, Equatable, Sendable {
    let id: String
    var selectedSiteName: String?
    var selectedResolution: String?
    var selectedQuality: String?
    var selectedCodec: String?
    var showPromotionOnly: Bool
    var hideHitAndRun: Bool
    var sortField: SearchResultSortField
    var sortOrder: SearchResultSortOrder
    let siteOptions: [SearchResultFilterOptionViewState]
    let resolutionOptions: [SearchResultFilterOptionViewState]
    let qualityOptions: [SearchResultFilterOptionViewState]
    let codecOptions: [SearchResultFilterOptionViewState]
}
