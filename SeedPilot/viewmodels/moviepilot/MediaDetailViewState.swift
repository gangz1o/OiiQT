import Foundation

nonisolated struct ActorViewState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let characterName: String
    let profileURLString: String
}

nonisolated struct MediaDetailViewState: Identifiable, Equatable, Sendable {
    var id: String
    var posterURLString: String
    var backdropURLString: String
    var title: String
    var ratingText: String
    var isSeries: Bool
    var overviewText: String?
    var actors: [ActorViewState]
    var isOverviewLoading: Bool
    var isActorsLoading: Bool
    var isSubscribed: Bool
    var searchResults: [SearchResultViewState]
    var isSearchLoading: Bool
    var isSubscribeLoading: Bool
    var searchFeedbackText: String?

    static func bootstrap(from card: MediaCardViewState) -> MediaDetailViewState {
        MediaDetailViewState(
            id: card.id,
            posterURLString: card.posterURLString,
            backdropURLString: "",
            title: card.title,
            ratingText: card.ratingText,
            isSeries: card.isSeries,
            overviewText: nil,
            actors: [],
            isOverviewLoading: true,
            isActorsLoading: true,
            isSubscribed: false,
            searchResults: [],
            isSearchLoading: false,
            isSubscribeLoading: false,
            searchFeedbackText: nil
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
            overviewText: nil,
            actors: [],
            isOverviewLoading: true,
            isActorsLoading: true,
            isSubscribed: false,
            searchResults: [],
            isSearchLoading: false,
            isSubscribeLoading: false,
            searchFeedbackText: nil
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

nonisolated enum SubscribeFormFieldControl: String, Equatable, Sendable {
    case picker
    case toggle
    case text
}

nonisolated struct SubscribeFormOptionViewState: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var value: String
    var subtitle: String
}

nonisolated struct SubscribeFormFieldViewState: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var control: SubscribeFormFieldControl
    var selectedOptionID: String?
    var textValue: String
    var toggleValue: Bool
    var placeholder: String
    var footerText: String
    var options: [SubscribeFormOptionViewState]
    var isRequired: Bool
}

nonisolated struct SubscribeFormSectionViewState: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var fields: [SubscribeFormFieldViewState]
}

nonisolated struct SubscribeFormViewState: Identifiable, Equatable, Sendable {
    var id: String
    var mediaID: String
    var subscriptionID: Int?
    var mediaTitle: String
    var sheetTitle: String
    var sections: [SubscribeFormSectionViewState]
    var confirmButtonTitle: String
    var isSubmitting: Bool
    var statusText: String?
}
