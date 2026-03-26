import Foundation
import Observation

@MainActor
@Observable
final class MediaDetailViewModel {
    nonisolated private static let movieTypeName = "电影"
    nonisolated private static let tvTypeName = "电视剧"
    nonisolated private static let tmdbPosterBaseURLString = "https://image.tmdb.org/t/p/w500"

    @ObservationIgnored
    private let serverStore: MoviePilotServerStore

    @ObservationIgnored
    private let apiClient: MoviePilotMediaDetailAPIClient

    private(set) var viewState: MediaDetailViewState
    private(set) var showSubscribeSheet = false
    private(set) var subscribeFormViewState: SubscribeFormViewState?
    private(set) var searchFilterSheetViewState: SearchResultFilterSheetViewState?
    private(set) var downloadFormViewState: DownloadFormViewState?

    private var detailContext: MoviePilotMediaDetailContext
    private var isLoadingDetail = false
    private var searchFilterState = SearchResultFilterState.default

    /// Raw DTO lookup table — retained so we can serialize torrent_in back for download requests.
    @ObservationIgnored
    private var torrentRawJSONByResultID: [String: Data] = [:]

    convenience init(initialViewState: MediaDetailViewState) {
        self.init(
            initialViewState: initialViewState,
            serverStore: .shared,
            apiClient: .shared
        )
    }

    init(
        initialViewState: MediaDetailViewState,
        serverStore: MoviePilotServerStore,
        apiClient: MoviePilotMediaDetailAPIClient
    ) {
        self.serverStore = serverStore
        self.apiClient = apiClient
        viewState = initialViewState
        detailContext = Self.makeInitialContext(from: initialViewState)
    }

    func loadDetail(id: String) async {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        guard let requestContext = availableServerContext() else {
            viewState.isOverviewLoading = false
            viewState.isActorsLoading = false
            if viewState.overviewText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                viewState.overviewText = "请先配置 MoviePilot 服务器。"
            }
            return
        }

        let contextSnapshot = detailContext
        let viewStateSnapshot = viewState

        async let detailTask = fetchDetailSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            context: contextSnapshot
        )
        async let actorsTask = fetchCreditsSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            context: contextSnapshot
        )
        async let subscriptionTask = fetchSubscriptionSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            context: contextSnapshot
        )

        let detail = await detailTask
        let actors = await actorsTask
        let subscription = await subscriptionTask

        let payload = await Task.detached(priority: .userInitiated) {
            Self.makeDetailPayload(
                currentViewState: viewStateSnapshot,
                fallbackContext: contextSnapshot,
                detail: detail,
                actors: actors,
                subscription: subscription,
                baseURLString: requestContext.baseURLString,
                token: requestContext.token
            )
        }.value

        guard detailContext.mediaID == id else { return }

        detailContext = payload.context
        viewState = payload.viewState
    }

    func intentSearch() {
        guard !viewState.isSearchLoading else { return }

        viewState.isSearchLoading = true
        viewState.searchFeedbackText = "正在搜索资源..."
        viewState.searchResults = []

        Task {
            await performSearch()
        }
    }

    func intentSubscribe() {
        guard !viewState.isSubscribeLoading else { return }

        viewState.isSubscribeLoading = true

        Task {
            await prepareSubscribeForm()
        }
    }

    func dismissSubscribeSheet() {
        showSubscribeSheet = false
    }

    // MARK: - Download Actions

    /// Called when user taps a search result row — prepares the download form and opens the sheet.
    func prepareDownloadForm(for resultID: String) async {
        guard let result = viewState.searchResults.first(where: { $0.id == resultID }),
              torrentRawJSONByResultID[resultID] != nil else { return }
        guard let requestContext = availableServerContext() else { return }

        // Show sheet immediately with empty downloaders (loading state)
        downloadFormViewState = DownloadFormViewState(
            id: resultID,
            resourceTitle: result.title,
            downloaders: [],
            selectedDownloaderID: nil,
            savePath: "",
            isSubmitting: false,
            errorMessage: nil
        )

        // Fetch downloaders in background
        let clients = await fetchDownloadersSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token
        )

        guard downloadFormViewState?.id == resultID else { return }

        let options = clients.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { DownloaderOptionViewState(id: $0.id, name: $0.name) }

        downloadFormViewState?.downloaders = options
        downloadFormViewState?.selectedDownloaderID = options.first?.id
    }

    func updateDownloadFormDownloader(_ downloaderID: String) {
        downloadFormViewState?.selectedDownloaderID = downloaderID
    }

    func updateDownloadFormSavePath(_ path: String) {
        downloadFormViewState?.savePath = path
    }

    func confirmDownload() async {
        guard let form = downloadFormViewState,
              let rawJSON = torrentRawJSONByResultID[form.id],
              let requestContext = availableServerContext() else { return }

        downloadFormViewState?.isSubmitting = true
        downloadFormViewState?.errorMessage = nil

        let selectedDownloaderName = form.downloaders.first(where: { $0.id == form.selectedDownloaderID })?.name

        do {
            let response = try await apiClient.requestDownloadAdd(
                baseURLString: requestContext.baseURLString,
                token: requestContext.token,
                torrentInfoRawJSON: rawJSON,
                downloader: selectedDownloaderName,
                savePath: form.savePath
            )
            if response.success == true {
                downloadFormViewState = nil
            } else {
                downloadFormViewState?.isSubmitting = false
                downloadFormViewState?.errorMessage = response.message ?? "下载失败，请重试。"
            }
        } catch {
            downloadFormViewState?.isSubmitting = false
            downloadFormViewState?.errorMessage = error.localizedDescription
        }
    }

    func cancelDownload() {
        downloadFormViewState = nil
    }

    var filteredSearchResults: [SearchResultViewState] {
        let filteredResults = viewState.searchResults.filter { result in
            Self.matches(selectedValue: searchFilterState.selectedSiteName, currentValue: result.siteName)
                && Self.matches(selectedValue: searchFilterState.selectedResolution, currentValue: result.resolutionTag)
                && Self.matches(selectedValue: searchFilterState.selectedQuality, currentValue: result.qualityTag)
                && Self.matches(selectedValue: searchFilterState.selectedCodec, currentValue: result.codecTag)
                && (!searchFilterState.showPromotionOnly || result.promotionTag != nil)
                && (!searchFilterState.hideHitAndRun || !result.isHitAndRun)
        }

        return Self.sortSearchResults(filteredResults, using: searchFilterState)
    }

    var activeSearchFilterCount: Int {
        var count = 0
        if searchFilterState.selectedSiteName != nil { count += 1 }
        if searchFilterState.selectedResolution != nil { count += 1 }
        if searchFilterState.selectedQuality != nil { count += 1 }
        if searchFilterState.selectedCodec != nil { count += 1 }
        if searchFilterState.showPromotionOnly { count += 1 }
        if searchFilterState.hideHitAndRun { count += 1 }
        if searchFilterState.sortField != .relevance || searchFilterState.sortOrder != .descending { count += 1 }
        return count
    }

    func presentSearchFilterSheet() {
        let normalizedState = Self.normalizedSearchFilterState(
            searchFilterState,
            results: viewState.searchResults
        )
        searchFilterState = normalizedState
        searchFilterSheetViewState = Self.makeSearchFilterSheetViewState(
            from: normalizedState,
            results: viewState.searchResults
        )
    }

    func cancelSearchFilterSheet() {
        searchFilterSheetViewState = nil
    }

    func applySearchFilterSheet() {
        guard let sheetViewState = searchFilterSheetViewState else { return }
        searchFilterState = Self.makeSearchFilterState(from: sheetViewState)
        searchFilterSheetViewState = nil
    }

    func resetSearchFilterSheet() {
        searchFilterSheetViewState = Self.makeSearchFilterSheetViewState(
            from: .default,
            results: viewState.searchResults
        )
    }

    func updateSearchFilterSite(_ siteName: String?) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.selectedSiteName = siteName
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterResolution(_ resolution: String?) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.selectedResolution = resolution
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterQuality(_ quality: String?) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.selectedQuality = quality
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterCodec(_ codec: String?) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.selectedCodec = codec
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterPromotionOnly(_ isEnabled: Bool) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.showPromotionOnly = isEnabled
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterHideHitAndRun(_ isEnabled: Bool) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.hideHitAndRun = isEnabled
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterSortField(_ sortField: SearchResultSortField) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.sortField = sortField
        searchFilterSheetViewState = sheet
    }

    func updateSearchFilterSortOrder(_ sortOrder: SearchResultSortOrder) {
        guard var sheet = searchFilterSheetViewState else { return }
        sheet.sortOrder = sortOrder
        searchFilterSheetViewState = sheet
    }

    func updateSubscribeOption(fieldID: String, optionID: String) {
        guard var form = subscribeFormViewState else { return }

        for sectionIndex in form.sections.indices {
            guard let fieldIndex = form.sections[sectionIndex].fields.firstIndex(where: { $0.id == fieldID }) else {
                continue
            }

            form.sections[sectionIndex].fields[fieldIndex].selectedOptionID = optionID
        }

        subscribeFormViewState = form
    }

    func updateSubscribeText(fieldID: String, text: String) {
        guard var form = subscribeFormViewState else { return }

        for sectionIndex in form.sections.indices {
            guard let fieldIndex = form.sections[sectionIndex].fields.firstIndex(where: { $0.id == fieldID }) else {
                continue
            }

            form.sections[sectionIndex].fields[fieldIndex].textValue = text
        }

        subscribeFormViewState = form
    }

    func updateSubscribeToggle(fieldID: String, isOn: Bool) {
        guard var form = subscribeFormViewState else { return }

        for sectionIndex in form.sections.indices {
            guard let fieldIndex = form.sections[sectionIndex].fields.firstIndex(where: { $0.id == fieldID }) else {
                continue
            }

            form.sections[sectionIndex].fields[fieldIndex].toggleValue = isOn
        }

        subscribeFormViewState = form
    }

    func submitSubscription(form: SubscribeFormViewState?) async {
        guard var form else { return }
        guard let requestContext = availableServerContext() else {
            form.isSubmitting = false
            form.statusText = "请先配置 MoviePilot 服务器。"
            subscribeFormViewState = form
            return
        }

        form.isSubmitting = true
        form.statusText = nil
        subscribeFormViewState = form

        let contextSnapshot = detailContext
        let payload = await Task.detached(priority: .userInitiated) {
            Self.makeSubscribePayload(
                form: form,
                context: contextSnapshot
            )
        }.value

        do {
            let response: MoviePilotActionResponseDTO
            if form.subscriptionID != nil {
                response = try await apiClient.updateSubscription(
                    baseURLString: requestContext.baseURLString,
                    token: requestContext.token,
                    payload: payload
                )
            } else {
                response = try await apiClient.createSubscription(
                    baseURLString: requestContext.baseURLString,
                    token: requestContext.token,
                    payload: payload
                )
            }

            guard response.success else {
                throw NSError(
                    domain: "MediaDetailViewModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: response.message ?? "订阅提交失败"]
                )
            }

            let refreshedSubscription = try? await apiClient.requestSubscription(
                baseURLString: requestContext.baseURLString,
                token: requestContext.token,
                mediaID: contextSnapshot.mediaID,
                season: contextSnapshot.season,
                title: contextSnapshot.title
            )

            viewState.isSubscribed = refreshedSubscription.map(Self.hasSubscription) ?? true
            viewState.isSubscribeLoading = false
            showSubscribeSheet = false
            subscribeFormViewState = nil
        } catch {
            form.isSubmitting = false
            form.statusText = error.localizedDescription
            subscribeFormViewState = form
            viewState.isSubscribeLoading = false
        }
    }

    private func performSearch() async {
        guard let requestContext = availableServerContext() else {
            viewState.isSearchLoading = false
            viewState.searchFeedbackText = "请先配置 MoviePilot 服务器。"
            return
        }

        let contextSnapshot = detailContext

        do {
            let torrents = try await apiClient.requestSearchResults(
                baseURLString: requestContext.baseURLString,
                token: requestContext.token,
                mediaID: contextSnapshot.mediaID,
                mediaType: contextSnapshot.typeName,
                title: contextSnapshot.title,
                year: contextSnapshot.year,
                season: contextSnapshot.season.map(String.init)
            )

            let rawCount = torrents.count
            let torrentDTOs = torrents.map(\.torrentInfo)
            let mappedResults = await Task.detached(priority: .userInitiated) {
                Self.makeSearchResultViewStates(from: torrentDTOs)
            }.value

            // Populate raw JSON lookup table for download requests
            var rawLookup: [String: Data] = [:]
            for (index, item) in torrents.enumerated() {
                let resultID = Self.normalizedSearchResultID(from: item.torrentInfo, index: index)
                rawLookup[resultID] = item.rawTorrentInfoJSON
            }
            torrentRawJSONByResultID = rawLookup

            guard detailContext.mediaID == contextSnapshot.mediaID else { return }

            searchFilterState = Self.normalizedSearchFilterState(
                searchFilterState,
                results: mappedResults
            )
            searchFilterSheetViewState = nil
            viewState.searchResults = mappedResults
            viewState.isSearchLoading = false
            if mappedResults.isEmpty {
                viewState.searchFeedbackText = "没有找到匹配资源。"
            } else {
                let filteredCount = rawCount - mappedResults.count
                viewState.searchFeedbackText = filteredCount > 0
                    ? "已找到 \(mappedResults.count) 个候选资源（已过滤 \(filteredCount) 条无效记录）"
                    : "已找到 \(mappedResults.count) 个候选资源"
            }
        } catch {
            guard detailContext.mediaID == contextSnapshot.mediaID else { return }

            searchFilterSheetViewState = nil
            viewState.searchResults = []
            viewState.isSearchLoading = false
            viewState.searchFeedbackText = error.localizedDescription
        }
    }

    private func prepareSubscribeForm() async {
        guard let requestContext = availableServerContext() else {
            viewState.isSubscribeLoading = false
            return
        }

        let contextSnapshot = detailContext

        async let subscriptionTask = fetchSubscriptionSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token,
            context: contextSnapshot
        )
        async let downloadersTask = fetchDownloadersSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token
        )
        async let categoriesTask = fetchCategoriesSafely(
            baseURLString: requestContext.baseURLString,
            token: requestContext.token
        )

        let subscription = await subscriptionTask
        let downloaders = await downloadersTask
        let categories = await categoriesTask

        let formViewState = await Task.detached(priority: .userInitiated) {
            Self.makeSubscribeFormViewState(
                context: contextSnapshot,
                existingSubscription: subscription,
                downloaders: downloaders,
                categories: categories
            )
        }.value

        guard detailContext.mediaID == contextSnapshot.mediaID else { return }

        subscribeFormViewState = formViewState
        showSubscribeSheet = true
        viewState.isSubscribeLoading = false
        viewState.isSubscribed = Self.hasSubscription(subscription)
    }

    private func availableServerContext() -> MoviePilotMediaRequestContext? {
        for server in serverStore.servers {
            guard let normalizedBaseURL = MoviePilotURLNormalizer.normalize(server.baseURLString) else {
                continue
            }

            let trimmedToken = serverStore.token(for: server.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedToken.isEmpty else {
                continue
            }

            return MoviePilotMediaRequestContext(
                baseURLString: normalizedBaseURL,
                token: trimmedToken
            )
        }

        return nil
    }

    private func fetchDetailSafely(
        baseURLString: String,
        token: String,
        context: MoviePilotMediaDetailContext
    ) async -> MPMediaDetailDTO? {
        do {
            return try await apiClient.requestMediaDetail(
                baseURLString: baseURLString,
                token: token,
                mediaID: context.mediaID,
                typeName: context.typeName,
                title: context.title,
                year: context.year
            )
        } catch {
            print("MoviePilot detail request failed for \(context.mediaID): \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchCreditsSafely(
        baseURLString: String,
        token: String,
        context: MoviePilotMediaDetailContext
    ) async -> MPMediaPersonListDTO {
        do {
            return try await apiClient.requestCredits(
                baseURLString: baseURLString,
                token: token,
                mediaID: context.mediaID,
                typeName: context.typeName
            )
        } catch {
            print("MoviePilot credits request failed for \(context.mediaID): \(error.localizedDescription)")
            return []
        }
    }

    private func fetchSubscriptionSafely(
        baseURLString: String,
        token: String,
        context: MoviePilotMediaDetailContext
    ) async -> MPSubscribeDTO? {
        do {
            return try await apiClient.requestSubscription(
                baseURLString: baseURLString,
                token: token,
                mediaID: context.mediaID,
                season: context.season,
                title: context.title
            )
        } catch {
            print("MoviePilot subscribe request failed for \(context.mediaID): \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchDownloadersSafely(
        baseURLString: String,
        token: String
    ) async -> MPDownloadClientListDTO {
        do {
            return try await apiClient.requestDownloadClients(
                baseURLString: baseURLString,
                token: token
            )
        } catch {
            print("MoviePilot downloader request failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchCategoriesSafely(
        baseURLString: String,
        token: String
    ) async -> [String: String] {
        do {
            return try await apiClient.requestMediaCategories(
                baseURLString: baseURLString,
                token: token
            )
        } catch {
            print("MoviePilot media category request failed: \(error.localizedDescription)")
            return [:]
        }
    }

    nonisolated private static func makeInitialContext(from viewState: MediaDetailViewState) -> MoviePilotMediaDetailContext {
        let identifiers = parseMediaIdentifier(from: viewState.id)
        return MoviePilotMediaDetailContext(
            mediaID: viewState.id,
            title: viewState.title,
            year: nil,
            season: nil,
            typeName: viewState.isSeries ? tvTypeName : movieTypeName,
            tmdbID: identifiers.tmdbID,
            doubanID: identifiers.doubanID,
            bangumiID: identifiers.bangumiID,
            posterURLString: viewState.posterURLString,
            backdropURLString: nil,
            overviewText: viewState.overviewText,
            ratingValue: Double(viewState.ratingText)
        )
    }

    nonisolated private static func makeDetailPayload(
        currentViewState: MediaDetailViewState,
        fallbackContext: MoviePilotMediaDetailContext,
        detail: MPMediaDetailDTO?,
        actors: MPMediaPersonListDTO,
        subscription: MPSubscribeDTO?,
        baseURLString: String,
        token: String
    ) -> MoviePilotMediaDetailPayload {
        let updatedContext = makeUpdatedContext(
            fallback: fallbackContext,
            detail: detail,
            baseURLString: baseURLString,
            token: token
        )

        var nextViewState = currentViewState
        nextViewState.id = updatedContext.mediaID
        nextViewState.posterURLString = updatedContext.posterURLString
        nextViewState.backdropURLString = updatedContext.backdropURLString ?? ""
        nextViewState.title = updatedContext.title
        nextViewState.ratingText = normalizedRatingText(from: detail) ?? currentViewState.ratingText
        nextViewState.isSeries = updatedContext.typeName == tvTypeName
        nextViewState.overviewText = updatedContext.overviewText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? updatedContext.overviewText
            : "暂无简介"
        nextViewState.actors = makeActorViewStates(
            from: actors,
            baseURLString: baseURLString,
            token: token
        )
        nextViewState.isOverviewLoading = false
        nextViewState.isActorsLoading = false
        nextViewState.isSubscribed = hasSubscription(subscription)
        nextViewState.isSubscribeLoading = false

        return MoviePilotMediaDetailPayload(
            context: updatedContext,
            viewState: nextViewState
        )
    }

    nonisolated private static func makeUpdatedContext(
        fallback: MoviePilotMediaDetailContext,
        detail: MPMediaDetailDTO?,
        baseURLString: String,
        token: String
    ) -> MoviePilotMediaDetailContext {
        guard let detail else {
            return fallback
        }

        let displayTitle = normalizedDisplayTitle(from: detail)
        let posterURLString = completedImageURLString(
            rawPath: detail.posterPath ?? detail.backdropPath,
            source: normalizedSource(from: detail),
            baseURLString: baseURLString,
            token: token,
            isTMDBFallback: detail.tmdbID != nil
        ) ?? fallback.posterURLString
        let backdropURLString = completedImageURLString(
            rawPath: detail.backdropPath ?? detail.posterPath,
            source: normalizedSource(from: detail),
            baseURLString: baseURLString,
            token: token,
            isTMDBFallback: detail.tmdbID != nil
        )

        return MoviePilotMediaDetailContext(
            mediaID: canonicalMediaID(from: detail, fallback: fallback.mediaID),
            title: displayTitle,
            year: detail.year?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallback.year,
            season: detail.season ?? fallback.season,
            typeName: normalizedTypeName(from: detail, fallbackIsSeries: fallback.typeName == tvTypeName),
            tmdbID: detail.tmdbID ?? fallback.tmdbID,
            doubanID: detail.doubanID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallback.doubanID,
            bangumiID: detail.bangumiID ?? fallback.bangumiID,
            posterURLString: posterURLString,
            backdropURLString: backdropURLString ?? fallback.backdropURLString,
            overviewText: detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallback.overviewText,
            ratingValue: ratingValue(from: detail) ?? fallback.ratingValue
        )
    }

    nonisolated private static func makeActorViewStates(
        from actors: MPMediaPersonListDTO,
        baseURLString: String,
        token: String
    ) -> [ActorViewState] {
        Array(
            actors.prefix(12).enumerated().map { index, actor in
                let identifier = actor.id.map(String.init) ?? "actor-\(index)"
                let rawImagePath = actor.profilePath?.nonEmpty ?? actor.avatarURLString?.nonEmpty

                return ActorViewState(
                    id: identifier,
                    name: actor.name?.nonEmpty ?? "未知演员",
                    characterName: actor.character?.nonEmpty ?? "",
                    profileURLString: completedImageURLString(
                        rawPath: rawImagePath,
                        source: normalizedSource(from: actor.source),
                        baseURLString: baseURLString,
                        token: token,
                        isTMDBFallback: actor.profilePath?.hasPrefix("/") == true
                    ) ?? ""
                )
            }
        )
    }

    nonisolated private static func makeSearchResultViewStates(
        from torrents: MPTorrentListDTO
    ) -> [SearchResultViewState] {
        torrents.enumerated().compactMap { index, torrent in
            guard torrent.title?.nonEmpty != nil || torrent.siteName?.nonEmpty != nil else {
                return nil
            }
            return makeSearchResultViewState(from: torrent, index: index)
        }
    }

    nonisolated private static func makeSearchResultViewState(
        from torrent: MPTorrentInfoDTO,
        index: Int
    ) -> SearchResultViewState {
        let promotionTag = normalizedPromotionTag(
            volumeFactor: torrent.volumeFactor,
            downloadVolumeFactor: torrent.downloadVolumeFactor,
            uploadVolumeFactor: torrent.uploadVolumeFactor
        )
        let badges = makeSearchResultBadges(from: torrent, excludingPromotionTag: promotionTag)

        return SearchResultViewState(
            id: normalizedSearchResultID(from: torrent, index: index),
            sortPriority: torrent.priOrder ?? index,
            siteName: normalizedSearchResultSiteName(from: torrent),
            seedersCount: max(torrent.seeders ?? 0, 0),
            leechersCount: max(torrent.peers ?? 0, 0),
            title: normalizedSearchResultTitle(from: torrent),
            subtitle: normalizedSearchResultSubtitle(from: torrent),
            sizeInBytes: Int64(torrent.size ?? 0),
            sizeString: normalizedSizeText(from: torrent.size),
            publishTimestamp: normalizedPublishTimestamp(from: torrent.pubdate),
            timeString: normalizedTimeText(
                dateElapsed: torrent.dateElapsed,
                pubdate: torrent.pubdate
            ),
            promotionTag: promotionTag,
            promotionPalette: promotionPalette(
                promotionTag: promotionTag,
                downloadVolumeFactor: torrent.downloadVolumeFactor,
                uploadVolumeFactor: torrent.uploadVolumeFactor
            ),
            badges: badges,
            qualityTag: searchResultQualityTag(from: badges),
            resolutionTag: searchResultResolutionTag(from: badges),
            codecTag: searchResultCodecTag(from: badges),
            isHitAndRun: torrent.hitAndRun == true,
            pageURLString: torrent.pageURL?.nonEmpty ?? ""
        )
    }

    nonisolated private static func makeSubscribeFormViewState(
        context: MoviePilotMediaDetailContext,
        existingSubscription: MPSubscribeDTO?,
        downloaders: MPDownloadClientListDTO,
        categories: [String: String]
    ) -> SubscribeFormViewState {
        let downloaderOptions = downloaders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { downloader in
            SubscribeFormOptionViewState(
                id: downloader.id,
                title: downloader.name,
                value: downloader.name,
                subtitle: downloader.subtitle
            )
        }

        let categoryOptions = categories.keys.sorted {
            (categories[$0] ?? "").localizedCaseInsensitiveCompare(categories[$1] ?? "") == .orderedAscending
        }.map { key in
            SubscribeFormOptionViewState(
                id: key,
                title: categories[key] ?? key,
                value: key,
                subtitle: key
            )
        }

        let strategySection = SubscribeFormSectionViewState(
            id: "section-strategy",
            title: "筛选策略",
            fields: [
                makeTextField(
                    id: SubscribeFieldID.quality,
                    title: "清晰度",
                    value: existingSubscription?.quality,
                    placeholder: "例如：BluRay / WEB-DL"
                ),
                makeTextField(
                    id: SubscribeFieldID.resolution,
                    title: "分辨率",
                    value: existingSubscription?.resolution,
                    placeholder: "例如：1080p / 2160p"
                ),
                makeTextField(
                    id: SubscribeFieldID.effect,
                    title: "特效规格",
                    value: existingSubscription?.effect,
                    placeholder: "例如：HDR / Dolby Vision"
                ),
                makeTextField(
                    id: SubscribeFieldID.filter,
                    title: "过滤规则",
                    value: existingSubscription?.filter,
                    placeholder: "填写服务端支持的过滤表达式"
                ),
                makeTextField(
                    id: SubscribeFieldID.include,
                    title: "包含关键词",
                    value: existingSubscription?.include,
                    placeholder: "多个关键词用空格分隔"
                ),
                makeTextField(
                    id: SubscribeFieldID.exclude,
                    title: "排除关键词",
                    value: existingSubscription?.exclude,
                    placeholder: "排除噪音版本或小组"
                ),
                SubscribeFormFieldViewState(
                    id: SubscribeFieldID.bestVersion,
                    title: "自动洗版",
                    control: .toggle,
                    selectedOptionID: nil,
                    textValue: "",
                    toggleValue: (existingSubscription?.bestVersion ?? 0) > 0,
                    placeholder: "",
                    footerText: "开启后允许按更优版本持续升级",
                    options: [],
                    isRequired: false
                )
            ]
        )

        let storageSection = SubscribeFormSectionViewState(
            id: "section-storage",
            title: "下载与归档",
            fields: [
                SubscribeFormFieldViewState(
                    id: SubscribeFieldID.downloader,
                    title: "下载器",
                    control: .picker,
                    selectedOptionID: selectedOptionID(
                        matchingValue: existingSubscription?.downloader,
                        options: downloaderOptions
                    ),
                    textValue: "",
                    toggleValue: false,
                    placeholder: "",
                    footerText: "使用当前 MoviePilot 可用下载器列表",
                    options: downloaderOptions,
                    isRequired: false
                ),
                SubscribeFormFieldViewState(
                    id: SubscribeFieldID.mediaCategory,
                    title: "自动分类",
                    control: .picker,
                    selectedOptionID: selectedOptionID(
                        matchingValue: existingSubscription?.mediaCategory,
                        options: categoryOptions
                    ),
                    textValue: "",
                    toggleValue: false,
                    placeholder: "",
                    footerText: "读取服务器自动分类配置",
                    options: categoryOptions,
                    isRequired: false
                ),
                makeTextField(
                    id: SubscribeFieldID.savePath,
                    title: "存储路径",
                    value: existingSubscription?.savePath,
                    placeholder: "例如：/downloads/media"
                )
            ]
        )

        let searchSection = SubscribeFormSectionViewState(
            id: "section-search",
            title: "搜索控制",
            fields: [
                makeTextField(
                    id: SubscribeFieldID.customWords,
                    title: "自定义识别词",
                    value: existingSubscription?.customWords,
                    placeholder: "补充别名、制作组或地区信息"
                ),
                SubscribeFormFieldViewState(
                    id: SubscribeFieldID.searchImdbid,
                    title: "优先使用 IMDb 搜索",
                    control: .toggle,
                    selectedOptionID: nil,
                    textValue: "",
                    toggleValue: (existingSubscription?.searchImdbid ?? 0) > 0,
                    placeholder: "",
                    footerText: "打开后会在搜索阶段带上 IMDb 识别信息",
                    options: [],
                    isRequired: false
                )
            ]
        )

        return SubscribeFormViewState(
            id: "subscribe-form-\(context.mediaID)",
            mediaID: context.mediaID,
            subscriptionID: existingSubscription?.id,
            mediaTitle: context.title,
            sheetTitle: existingSubscription?.id == nil ? "订阅设置" : "编辑订阅",
            sections: [strategySection, storageSection, searchSection],
            confirmButtonTitle: existingSubscription?.id == nil ? "创建订阅" : "更新订阅",
            isSubmitting: false,
            statusText: existingSubscription?.id == nil ? nil : "当前媒体已存在订阅，可直接调整策略。"
        )
    }

    nonisolated private static func makeSubscribePayload(
        form: SubscribeFormViewState,
        context: MoviePilotMediaDetailContext
    ) -> MPSubscribeDTO {
        var payload = MPSubscribeDTO()
        payload.id = form.subscriptionID
        payload.name = context.title.nonEmpty
        payload.year = context.year?.nonEmpty
        payload.type = context.typeName
        payload.tmdbid = context.tmdbID
        payload.doubanid = context.doubanID?.nonEmpty
        payload.bangumiid = context.bangumiID
        payload.mediaid = context.mediaID
        payload.season = context.season
        payload.poster = context.posterURLString.nonEmpty
        payload.backdrop = context.backdropURLString?.nonEmpty
        payload.vote = context.ratingValue
        payload.description = context.overviewText?.nonEmpty
        payload.quality = selectedFieldText(id: SubscribeFieldID.quality, from: form)
        payload.resolution = selectedFieldText(id: SubscribeFieldID.resolution, from: form)
        payload.effect = selectedFieldText(id: SubscribeFieldID.effect, from: form)
        payload.filter = selectedFieldText(id: SubscribeFieldID.filter, from: form)
        payload.include = selectedFieldText(id: SubscribeFieldID.include, from: form)
        payload.exclude = selectedFieldText(id: SubscribeFieldID.exclude, from: form)
        payload.bestVersion = selectedFieldToggle(id: SubscribeFieldID.bestVersion, from: form) ? 1 : 0
        payload.downloader = selectedFieldOptionValue(id: SubscribeFieldID.downloader, from: form)
        payload.mediaCategory = selectedFieldOptionValue(id: SubscribeFieldID.mediaCategory, from: form)
        payload.savePath = selectedFieldText(id: SubscribeFieldID.savePath, from: form)
        payload.customWords = selectedFieldText(id: SubscribeFieldID.customWords, from: form)
        payload.searchImdbid = selectedFieldToggle(id: SubscribeFieldID.searchImdbid, from: form) ? 1 : 0
        return payload
    }

    nonisolated private static func hasSubscription(_ subscription: MPSubscribeDTO?) -> Bool {
        guard let subscription else { return false }
        if subscription.id != nil {
            return true
        }

        return subscription.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    nonisolated private static func selectedFieldText(
        id: String,
        from form: SubscribeFormViewState
    ) -> String? {
        selectedField(id: id, from: form)?.textValue.nonEmpty
    }

    nonisolated private static func selectedFieldToggle(
        id: String,
        from form: SubscribeFormViewState
    ) -> Bool {
        selectedField(id: id, from: form)?.toggleValue ?? false
    }

    nonisolated private static func selectedFieldOptionValue(
        id: String,
        from form: SubscribeFormViewState
    ) -> String? {
        guard let field = selectedField(id: id, from: form),
              let selectedOptionID = field.selectedOptionID else {
            return nil
        }

        return field.options.first(where: { $0.id == selectedOptionID })?.value.nonEmpty
    }

    nonisolated private static func selectedField(
        id: String,
        from form: SubscribeFormViewState
    ) -> SubscribeFormFieldViewState? {
        for section in form.sections {
            if let field = section.fields.first(where: { $0.id == id }) {
                return field
            }
        }

        return nil
    }

    nonisolated private static func makeTextField(
        id: String,
        title: String,
        value: String?,
        placeholder: String
    ) -> SubscribeFormFieldViewState {
        SubscribeFormFieldViewState(
            id: id,
            title: title,
            control: .text,
            selectedOptionID: nil,
            textValue: value ?? "",
            toggleValue: false,
            placeholder: placeholder,
            footerText: "",
            options: [],
            isRequired: false
        )
    }

    nonisolated private static func selectedOptionID(
        matchingValue value: String?,
        options: [SubscribeFormOptionViewState]
    ) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return options.first(where: { $0.value == value || $0.id == value })?.id
    }

    nonisolated private static func normalizedDisplayTitle(from dto: MPMediaItemDTO) -> String {
        let candidates = [
            dto.title,
            dto.name,
            dto.originalTitle,
            dto.originalName,
            dto.enTitle
        ]

        for candidate in candidates {
            if let nonEmpty = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                return nonEmpty
            }
        }

        return "未知标题"
    }

    nonisolated private static func normalizedTypeName(
        from dto: MPMediaItemDTO,
        fallbackIsSeries: Bool
    ) -> String {
        let rawType = dto.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if rawType.contains("剧")
            || rawType.contains("tv")
            || rawType.contains("series")
            || rawType.contains("anime")
            || rawType.contains("bangumi") {
            return tvTypeName
        }

        if rawType.contains("影") || rawType.contains("movie") {
            return movieTypeName
        }

        return fallbackIsSeries ? tvTypeName : movieTypeName
    }

    nonisolated private static func canonicalMediaID(
        from dto: MPMediaItemDTO,
        fallback: String
    ) -> String {
        if let mediaID = dto.mediaID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            if mediaID.contains(":") {
                return mediaID
            }

            let prefix = dto.mediaIDPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty
                ?? dto.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty
            if let prefix {
                return "\(prefix):\(mediaID)"
            }

            return mediaID
        }

        if let tmdbID = dto.tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let doubanID = dto.doubanID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return "douban:\(doubanID)"
        }

        if let bangumiID = dto.bangumiID {
            return "bangumi:\(bangumiID)"
        }

        return fallback
    }

    nonisolated private static func normalizedRatingText(from dto: MPMediaItemDTO?) -> String? {
        guard let dto,
              let ratingValue = ratingValue(from: dto),
              ratingValue > 0 else {
            return nil
        }

        return String(format: "%.1f", ratingValue)
    }

    nonisolated private static func ratingValue(from dto: MPMediaItemDTO) -> Double? {
        if let voteAverage = dto.voteAverage, voteAverage > 0 {
            return voteAverage
        }

        if let ratingValue = dto.rating?.value, ratingValue > 0 {
            return ratingValue
        }

        return nil
    }

    nonisolated private static func normalizedSizeText(from rawSize: Double?) -> String {
        guard let rawSize, rawSize > 0 else {
            return "大小未知"
        }

        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = rawSize
        var unitIndex = 0

        while size >= 1024, unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", size, units[unitIndex])
    }

    nonisolated private static func normalizedSearchResultID(
        from torrent: MPTorrentInfoDTO,
        index: Int
    ) -> String {
        if let pageURLString = torrent.pageURL?.nonEmpty {
            return pageURLString
        }

        let components = [
            torrent.site.map(String.init),
            normalizedSearchResultTitle(from: torrent),
            torrent.pubdate?.nonEmpty,
            String(index)
        ].compactMap { $0 }

        return components.joined(separator: "|")
    }

    nonisolated private static func normalizedSearchResultSiteName(
        from torrent: MPTorrentInfoDTO
    ) -> String {
        torrent.siteName?.nonEmpty ?? "未知站点"
    }

    nonisolated private static func normalizedSearchResultTitle(
        from torrent: MPTorrentInfoDTO
    ) -> String {
        normalizedSearchText(torrent.title) ?? "未知资源"
    }

    nonisolated private static func normalizedSearchResultSubtitle(
        from torrent: MPTorrentInfoDTO
    ) -> String {
        normalizedSearchText(torrent.description) ?? "暂无副标题"
    }

    nonisolated private static func normalizedSearchText(_ rawText: String?) -> String? {
        rawText?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    nonisolated private static func normalizedTimeText(
        dateElapsed: String?,
        pubdate: String?
    ) -> String {
        if let elapsed = normalizedSearchText(dateElapsed) {
            return elapsed
        }

        guard let rawPublishTime = normalizedSearchText(pubdate) else {
            return "时间未知"
        }

        if containsRelativeTimeKeyword(in: rawPublishTime) {
            return rawPublishTime
        }

        guard let publishDate = parsedSearchResultDate(from: rawPublishTime) else {
            return "时间未知"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: publishDate, relativeTo: Date())
    }

    nonisolated private static func normalizedPublishTimestamp(from rawPublishTime: String?) -> TimeInterval? {
        guard let publishDate = parsedSearchResultDate(from: normalizedSearchText(rawPublishTime) ?? "") else {
            return nil
        }

        return publishDate.timeIntervalSince1970
    }

    nonisolated private static func containsRelativeTimeKeyword(in text: String) -> Bool {
        let normalizedText = text.lowercased()
        let keywords = ["前", "刚刚", "ago", "hour", "day", "week", "month", "year", "min"]
        return keywords.contains { normalizedText.contains($0) }
    }

    nonisolated private static func parsedSearchResultDate(from rawText: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: rawText) {
            return date
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackISOFormatter.date(from: rawText) {
            return date
        }

        let dateFormats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "EEE, dd MMM yyyy HH:mm:ss Z"
        ]

        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format

            if let date = formatter.date(from: rawText) {
                return date
            }
        }

        return nil
    }

    nonisolated private static func normalizedPromotionTag(
        volumeFactor: String?,
        downloadVolumeFactor: Double?,
        uploadVolumeFactor: Double?
    ) -> String? {
        let trimmedVolumeFactor = normalizedSearchText(volumeFactor)
        let isDiscount = (downloadVolumeFactor ?? 1) < 1
        let isFree = downloadVolumeFactor == 0
        let isBonus = (uploadVolumeFactor ?? 1) > 1

        if isFree || isDiscount || isBonus {
            if let trimmedVolumeFactor, !isNeutralPromotionText(trimmedVolumeFactor) {
                return trimmedVolumeFactor
            }

            if isFree {
                return "免费"
            }

            if let downloadVolumeFactor, downloadVolumeFactor > 0, downloadVolumeFactor < 1 {
                return String(format: "%.0f%%", downloadVolumeFactor * 100)
            }

            if let uploadVolumeFactor, uploadVolumeFactor > 1 {
                return String(format: "%.1fx", uploadVolumeFactor)
            }
        }

        return nil
    }

    nonisolated private static func isNeutralPromotionText(_ text: String) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1.0", "1", "100%", "normal"].contains(normalizedText)
    }

    nonisolated private static func promotionPalette(
        promotionTag: String?,
        downloadVolumeFactor: Double?,
        uploadVolumeFactor: Double?
    ) -> SearchResultBadgePaletteViewState? {
        guard promotionTag != nil else { return nil }

        if downloadVolumeFactor == 0 {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#156F50",
                backgroundHex: "#DDF7EA"
            )
        }

        if let downloadVolumeFactor, downloadVolumeFactor < 1 {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#C96B00",
                backgroundHex: "#FFF0DF"
            )
        }

        if let uploadVolumeFactor, uploadVolumeFactor > 1 {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#6F42C1",
                backgroundHex: "#F1E9FF"
            )
        }

        return SearchResultBadgePaletteViewState(
            foregroundHex: "#6F42C1",
            backgroundHex: "#F1E9FF"
        )
    }

    nonisolated private static func makeSearchResultBadges(
        from torrent: MPTorrentInfoDTO,
        excludingPromotionTag promotionTag: String?
    ) -> [SearchResultBadgeViewState] {
        var orderedBadgeTexts: [String] = []
        var seenBadgeKeys = Set<String>()

        for label in torrent.labels {
            appendSearchResultBadgeText(
                canonicalSearchResultBadgeText(from: label),
                excludingPromotionTag: promotionTag,
                to: &orderedBadgeTexts,
                seenBadgeKeys: &seenBadgeKeys
            )
        }

        for supplementalToken in supplementalSearchResultBadgeTexts(from: torrent) {
            appendSearchResultBadgeText(
                supplementalToken,
                excludingPromotionTag: promotionTag,
                to: &orderedBadgeTexts,
                seenBadgeKeys: &seenBadgeKeys
            )
        }

        if torrent.hitAndRun == true {
            appendSearchResultBadgeText(
                "H&R",
                excludingPromotionTag: promotionTag,
                to: &orderedBadgeTexts,
                seenBadgeKeys: &seenBadgeKeys
            )
        }

        if let freeDateDiff = normalizedSearchText(torrent.freeDateDiff) {
            appendSearchResultBadgeText(
                freeDateDiff,
                excludingPromotionTag: promotionTag,
                to: &orderedBadgeTexts,
                seenBadgeKeys: &seenBadgeKeys
            )
        }

        return orderedBadgeTexts.map { badgeText in
            SearchResultBadgeViewState(
                id: badgeText.lowercased(),
                text: badgeText,
                palette: badgePalette(for: badgeText)
            )
        }
    }

    nonisolated private static func appendSearchResultBadgeText(
        _ rawText: String?,
        excludingPromotionTag promotionTag: String?,
        to orderedBadgeTexts: inout [String],
        seenBadgeKeys: inout Set<String>
    ) {
        guard let rawText = normalizedSearchText(rawText) else { return }
        if let promotionTag, rawText.caseInsensitiveCompare(promotionTag) == .orderedSame {
            return
        }

        let normalizedKey = rawText.lowercased()
        guard !seenBadgeKeys.contains(normalizedKey) else { return }

        seenBadgeKeys.insert(normalizedKey)
        orderedBadgeTexts.append(rawText)
    }

    nonisolated private static func supplementalSearchResultBadgeTexts(
        from torrent: MPTorrentInfoDTO
    ) -> [String] {
        let searchableText = [
            torrent.title,
            torrent.description
        ]
            .compactMap(normalizedSearchText)
            .joined(separator: " ")

        guard !searchableText.isEmpty else { return [] }

        let normalizedText = searchableText.lowercased()
        let rules: [(token: String, patterns: [String])] = [
            ("BluRay DIY", ["bluray diy", "blu-ray diy"]),
            ("BluRay", ["bluray", "blu-ray", "bdrip", "bdmv"]),
            ("WEB-DL", ["web-dl", "webdl"]),
            ("WEBRip", ["webrip"]),
            ("Remux", ["remux"]),
            ("UHD HDR", ["uhd hdr"]),
            ("Dolby Vision", ["dolby vision"]),
            ("2160p", ["2160p", "4k"]),
            ("1080p", ["1080p"]),
            ("720p", ["720p"]),
            ("x265", ["x265", "h265"]),
            ("x264", ["x264", "h264"]),
            ("HEVC", ["hevc"]),
            ("AV1", ["av1"]),
            ("VC1", ["vc-1", "vc1"]),
            ("10bit", ["10bit", "10-bit"]),
            ("HDR", ["hdr10+", "hdr10", "hdr"]),
            ("中字", ["中字", "简中", "繁中", "中文字幕"]),
            ("国语", ["国语", "国配", "国语配音"])
        ]

        var tokens: [String] = []
        for rule in rules {
            if rule.patterns.contains(where: { normalizedText.contains($0) }) {
                tokens.append(rule.token)
            }
        }

        return tokens
    }

    nonisolated private static func canonicalSearchResultBadgeText(
        from rawText: String
    ) -> String? {
        guard let normalizedText = normalizedSearchText(rawText) else { return nil }
        let lowercasedText = normalizedText.lowercased()

        let canonicalTokens: [(patterns: [String], replacement: String)] = [
            (["bluray diy", "blu-ray diy"], "BluRay DIY"),
            (["bluray", "blu-ray", "bdrip", "bdmv"], "BluRay"),
            (["web-dl", "webdl"], "WEB-DL"),
            (["webrip"], "WEBRip"),
            (["remux"], "Remux"),
            (["2160p", "4k"], "2160p"),
            (["1080p"], "1080p"),
            (["720p"], "720p"),
            (["x265", "h265"], "x265"),
            (["x264", "h264"], "x264"),
            (["hevc"], "HEVC"),
            (["av1"], "AV1"),
            (["vc-1", "vc1"], "VC1"),
            (["10bit", "10-bit"], "10bit"),
            (["hdr10+", "hdr10", "hdr"], "HDR"),
            (["dolby vision"], "Dolby Vision"),
            (["中字", "简中", "繁中", "中文字幕"], "中字"),
            (["国语", "国配", "国语配音"], "国语"),
            (["h&r", "hit and run"], "H&R")
        ]

        for token in canonicalTokens {
            if token.patterns.contains(where: { lowercasedText.contains($0) }) {
                return token.replacement
            }
        }

        return normalizedText
    }

    nonisolated private static func badgePalette(
        for badgeText: String
    ) -> SearchResultBadgePaletteViewState {
        let normalizedText = badgeText.lowercased()

        if normalizedText == "h&r" {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#FFFFFF",
                backgroundHex: "#303038"
            )
        }

        if normalizedText.contains("后") || normalizedText.contains("到期") {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#B03A6B",
                backgroundHex: "#FFE8F1"
            )
        }

        if ["bluray", "bluray diy", "web-dl", "webrip", "remux", "uhd hdr", "dolby vision", "hdr"].contains(normalizedText) {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#D94C3D",
                backgroundHex: "#FFEDE8"
            )
        }

        if ["2160p", "1080p", "720p"].contains(normalizedText) {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#7D43E6",
                backgroundHex: "#F0E9FF"
            )
        }

        if ["x265", "x264", "hevc", "av1", "vc1", "10bit"].contains(normalizedText) {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#C97A00",
                backgroundHex: "#FFF2DD"
            )
        }

        if ["中字", "国语"].contains(normalizedText) {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#5269C9",
                backgroundHex: "#E9EEFF"
            )
        }

        if isReleaseTeamBadge(normalizedText) {
            return SearchResultBadgePaletteViewState(
                foregroundHex: "#167B70",
                backgroundHex: "#E4F8F4"
            )
        }

        return SearchResultBadgePaletteViewState(
            foregroundHex: "#5D57C8",
            backgroundHex: "#ECEBFF"
        )
    }

    nonisolated private static func isReleaseTeamBadge(_ text: String) -> Bool {
        let compactText = text.replacingOccurrences(of: " ", with: "")
        let pattern = "^[a-z0-9-]{3,12}$"
        let range = compactText.range(of: pattern, options: .regularExpression) != nil
        let containsLetter = compactText.rangeOfCharacter(from: .letters) != nil
        return range && containsLetter && !compactText.contains("p")
    }

    nonisolated private static func searchResultQualityTag(
        from badges: [SearchResultBadgeViewState]
    ) -> String? {
        firstMatchingBadge(
            in: badges,
            allowedValues: ["BluRay DIY", "BluRay", "WEB-DL", "WEBRip", "Remux", "UHD HDR", "Dolby Vision", "HDR"]
        )
    }

    nonisolated private static func searchResultResolutionTag(
        from badges: [SearchResultBadgeViewState]
    ) -> String? {
        firstMatchingBadge(in: badges, allowedValues: ["2160p", "1080p", "720p"])
    }

    nonisolated private static func searchResultCodecTag(
        from badges: [SearchResultBadgeViewState]
    ) -> String? {
        firstMatchingBadge(in: badges, allowedValues: ["x265", "x264", "HEVC", "AV1", "VC1", "10bit"])
    }

    nonisolated private static func firstMatchingBadge(
        in badges: [SearchResultBadgeViewState],
        allowedValues: [String]
    ) -> String? {
        let allowedSet = Set(allowedValues.map { $0.lowercased() })
        return badges.first(where: { allowedSet.contains($0.text.lowercased()) })?.text
    }

    nonisolated private static func matches(
        selectedValue: String?,
        currentValue: String?
    ) -> Bool {
        guard let selectedValue else { return true }
        return selectedValue == currentValue
    }

    nonisolated private static func sortSearchResults(
        _ results: [SearchResultViewState],
        using filterState: SearchResultFilterState
    ) -> [SearchResultViewState] {
        results.sorted { lhs, rhs in
            let comparison = searchResultComparison(lhs, rhs, field: filterState.sortField)

            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }

            switch filterState.sortOrder {
            case .descending:
                return comparison == .orderedDescending
            case .ascending:
                return comparison == .orderedAscending
            }
        }
    }

    nonisolated private static func searchResultComparison(
        _ lhs: SearchResultViewState,
        _ rhs: SearchResultViewState,
        field: SearchResultSortField
    ) -> ComparisonResult {
        switch field {
        case .relevance:
            return compareIntegers(lhs.sortPriority, rhs.sortPriority)
        case .seeders:
            return compareIntegers(lhs.seedersCount, rhs.seedersCount)
        case .publishTime:
            return compareDoubles(lhs.publishTimestamp ?? 0, rhs.publishTimestamp ?? 0)
        case .size:
            return compareInt64(lhs.sizeInBytes, rhs.sizeInBytes)
        case .site:
            return lhs.siteName.localizedStandardCompare(rhs.siteName)
        }
    }

    nonisolated private static func compareIntegers(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    nonisolated private static func compareInt64(_ lhs: Int64, _ rhs: Int64) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    nonisolated private static func compareDoubles(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    nonisolated private static func normalizedSearchFilterState(
        _ filterState: SearchResultFilterState,
        results: [SearchResultViewState]
    ) -> SearchResultFilterState {
        var normalizedState = filterState

        let siteOptions = Set(results.map(\.siteName))
        let resolutionOptions = Set(results.compactMap(\.resolutionTag))
        let qualityOptions = Set(results.compactMap(\.qualityTag))
        let codecOptions = Set(results.compactMap(\.codecTag))

        if let selectedSiteName = normalizedState.selectedSiteName, !siteOptions.contains(selectedSiteName) {
            normalizedState.selectedSiteName = nil
        }
        if let selectedResolution = normalizedState.selectedResolution, !resolutionOptions.contains(selectedResolution) {
            normalizedState.selectedResolution = nil
        }
        if let selectedQuality = normalizedState.selectedQuality, !qualityOptions.contains(selectedQuality) {
            normalizedState.selectedQuality = nil
        }
        if let selectedCodec = normalizedState.selectedCodec, !codecOptions.contains(selectedCodec) {
            normalizedState.selectedCodec = nil
        }

        return normalizedState
    }

    nonisolated private static func makeSearchFilterState(
        from sheetViewState: SearchResultFilterSheetViewState
    ) -> SearchResultFilterState {
        SearchResultFilterState(
            selectedSiteName: sheetViewState.selectedSiteName,
            selectedResolution: sheetViewState.selectedResolution,
            selectedQuality: sheetViewState.selectedQuality,
            selectedCodec: sheetViewState.selectedCodec,
            showPromotionOnly: sheetViewState.showPromotionOnly,
            hideHitAndRun: sheetViewState.hideHitAndRun,
            sortField: sheetViewState.sortField,
            sortOrder: sheetViewState.sortOrder
        )
    }

    nonisolated private static func makeSearchFilterSheetViewState(
        from filterState: SearchResultFilterState,
        results: [SearchResultViewState]
    ) -> SearchResultFilterSheetViewState {
        let normalizedState = normalizedSearchFilterState(filterState, results: results)

        return SearchResultFilterSheetViewState(
            id: "search-filter-sheet",
            selectedSiteName: normalizedState.selectedSiteName,
            selectedResolution: normalizedState.selectedResolution,
            selectedQuality: normalizedState.selectedQuality,
            selectedCodec: normalizedState.selectedCodec,
            showPromotionOnly: normalizedState.showPromotionOnly,
            hideHitAndRun: normalizedState.hideHitAndRun,
            sortField: normalizedState.sortField,
            sortOrder: normalizedState.sortOrder,
            siteOptions: searchFilterOptions(
                from: results.map(\.siteName),
                ordering: .alphabetical
            ),
            resolutionOptions: searchFilterOptions(
                from: results.compactMap(\.resolutionTag),
                ordering: .resolution
            ),
            qualityOptions: searchFilterOptions(
                from: results.compactMap(\.qualityTag),
                ordering: .quality
            ),
            codecOptions: searchFilterOptions(
                from: results.compactMap(\.codecTag),
                ordering: .codec
            )
        )
    }

    nonisolated private static func searchFilterOptions(
        from values: [String],
        ordering: SearchFilterOptionOrdering
    ) -> [SearchResultFilterOptionViewState] {
        let uniqueValues = Array(Set(values))
        let sortedValues: [String]

        switch ordering {
        case .alphabetical:
            sortedValues = uniqueValues.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .resolution:
            let preferredOrder = ["2160p", "1080p", "720p"]
            sortedValues = sortByPreferredOrder(uniqueValues, preferredOrder: preferredOrder)
        case .quality:
            let preferredOrder = ["BluRay DIY", "BluRay", "Remux", "WEB-DL", "WEBRip", "UHD HDR", "Dolby Vision", "HDR"]
            sortedValues = sortByPreferredOrder(uniqueValues, preferredOrder: preferredOrder)
        case .codec:
            let preferredOrder = ["x265", "HEVC", "x264", "AV1", "VC1", "10bit"]
            sortedValues = sortByPreferredOrder(uniqueValues, preferredOrder: preferredOrder)
        }

        return sortedValues.map { value in
            SearchResultFilterOptionViewState(id: value, title: value)
        }
    }

    nonisolated private static func sortByPreferredOrder(
        _ values: [String],
        preferredOrder: [String]
    ) -> [String] {
        values.sorted { lhs, rhs in
            let lhsIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
            if lhsIndex == rhsIndex {
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            return lhsIndex < rhsIndex
        }
    }

    nonisolated private enum SearchFilterOptionOrdering {
        case alphabetical
        case resolution
        case quality
        case codec
    }

    nonisolated private static func parseMediaIdentifier(from mediaID: String) -> (
        tmdbID: Int?,
        doubanID: String?,
        bangumiID: Int?
    ) {
        let components = mediaID.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return (nil, nil, nil)
        }

        switch components[0].lowercased() {
        case "tmdb":
            return (Int(components[1]), nil, nil)
        case "douban":
            return (nil, components[1], nil)
        case "bangumi":
            return (nil, nil, Int(components[1]))
        default:
            return (nil, nil, nil)
        }
    }

    nonisolated private static func normalizedSource(from dto: MPMediaItemDTO) -> String {
        normalizedSource(from: dto.source)
    }

    nonisolated private static func normalizedSource(from rawSource: String?) -> String {
        rawSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    nonisolated private static func completedImageURLString(
        rawPath: String?,
        source: String,
        baseURLString: String,
        token: String,
        isTMDBFallback: Bool
    ) -> String? {
        guard let trimmedPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return nil
        }

        let lowercasedPath = trimmedPath.lowercased()
        let isTMDBSource = source == "tmdb" || isTMDBFallback
        let isDoubanSource = source == "douban"

        if lowercasedPath.hasPrefix("http://") || lowercasedPath.hasPrefix("https://") {
            if isDoubanSource {
                return normalizedDoubanImageURLString(trimmedPath)
            }
            return trimmedPath
        }

        if trimmedPath.hasPrefix("/api/") {
            return makeMoviePilotAbsoluteURL(
                baseURLString: baseURLString,
                relativePath: trimmedPath
            ) ?? trimmedPath
        }

        if trimmedPath.hasPrefix("/") {
            if isTMDBSource {
                return tmdbPosterBaseURLString + trimmedPath
            }

            if isDoubanSource {
                return normalizedDoubanImageURLString(trimmedPath)
            }

            return makeMoviePilotAbsoluteURL(
                baseURLString: baseURLString,
                relativePath: trimmedPath
            ) ?? trimmedPath
        }

        if isDoubanSource {
            return normalizedDoubanImageURLString(trimmedPath)
        }

        return makeMoviePilotAbsoluteURL(
            baseURLString: baseURLString,
            relativePath: trimmedPath
        ) ?? trimmedPath
    }

    nonisolated private static func normalizedDoubanImageURLString(_ rawPath: String) -> String {
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

    nonisolated private static func makeMoviePilotAbsoluteURL(
        baseURLString: String,
        relativePath: String
    ) -> String? {
        guard let baseURL = URL(string: baseURLString) else {
            return nil
        }

        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        return baseURL.appendingPathComponent(trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
    }

}

nonisolated private struct MoviePilotMediaRequestContext: Sendable, Equatable {
    let baseURLString: String
    let token: String
}

nonisolated private struct MoviePilotMediaDetailContext: Sendable, Equatable {
    let mediaID: String
    let title: String
    let year: String?
    let season: Int?
    let typeName: String
    let tmdbID: Int?
    let doubanID: String?
    let bangumiID: Int?
    let posterURLString: String
    let backdropURLString: String?
    let overviewText: String?
    let ratingValue: Double?
}

nonisolated private struct MoviePilotMediaDetailPayload: Sendable, Equatable {
    let context: MoviePilotMediaDetailContext
    let viewState: MediaDetailViewState
}

nonisolated private enum SubscribeFieldID {
    static let quality = "field-quality"
    static let resolution = "field-resolution"
    static let effect = "field-effect"
    static let filter = "field-filter"
    static let include = "field-include"
    static let exclude = "field-exclude"
    static let bestVersion = "field-best-version"
    static let downloader = "field-downloader"
    static let mediaCategory = "field-media-category"
    static let savePath = "field-save-path"
    static let customWords = "field-custom-words"
    static let searchImdbid = "field-search-imdbid"
}

private extension String {
    nonisolated var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
