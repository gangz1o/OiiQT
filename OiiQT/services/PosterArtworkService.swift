import Foundation
import SwiftData

enum PosterArtworkProvider: String, Sendable {
    case none
    case douban
    case tmdbCustom
    case tmdbBuiltIn
    case manualTMDB
    case manualDouban
}

@MainActor
final class PosterArtworkService {
    static let shared = PosterArtworkService()
    private static let doubanSuccessLookupTTL: TimeInterval = 60 * 60 * 24 * 30
    private static let doubanNegativeLookupTTL: TimeInterval = 60 * 60 * 12
    private static let doubanRateLimitLookupTTL: TimeInterval = 60 * 5
    private static let doubanNetworkLookupTTL: TimeInterval = 60 * 2
    private static let doubanDecodeLookupTTL: TimeInterval = 60 * 10
    private static let doubanBaseSuppressionInterval: TimeInterval = 20
    private static let doubanMaxSuppressionInterval: TimeInterval = 60 * 5

    private let urlCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 5_000
        return cache
    }()

    private let doubanSearchCoordinator = DoubanPosterSearchCoordinator(
        maxConcurrentRequests: 3,
        maxCachedEntries: 160
    )

    private var persistedMatchesByHash: [String: PersistedPosterMatchRecord] = [:]
    private var hasHydratedPersistedMatches = false
    private var persistedDoubanLookupsByKey: [String: PersistedDoubanLookupRecord] = [:]
    private var hasHydratedPersistedDoubanLookups = false
    private var doubanFailureStreak = 0
    private var doubanSuppressedUntil: Date?

    private init() {}

    func cachedPosterURL(for hash: String) -> URL? {
        cachedURL(for: hash)
    }

    func preparePosterCacheIfNeeded(context: ModelContext) {
        hydratePersistedMatchesIfNeeded(context: context)
        hydratePersistedDoubanLookupsIfNeeded(context: context)
        TMDBService.shared.preparePosterCacheIfNeeded(context: context)
    }

    func fetchPoster(hash: String, name: String, context: ModelContext) async -> URL? {
        preparePosterCacheIfNeeded(context: context)

        let titleCacheKey = cleanedTitleCacheKey(for: name)
        TransfersPosterDiagnostics.log(
            "poster fetch start hash=\(hash) titleCacheKey=\(titleCacheKey) name=\(name)"
        )

        if let persisted = persistedMatchesByHash[hash],
           persisted.isManualOverride,
           let persistedURL = persisted.posterURL {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=manual-persisted hash=\(hash) provider=\(persisted.provider.rawValue) url=\(persistedURL.absoluteString)"
            )
            cache(url: persistedURL, forHash: hash, titleCacheKey: titleCacheKey)
            return persistedURL
        }

        if let manualOverrideURL = TMDBService.shared.manualOverridePosterURL(for: hash, context: context) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=manual-tmdb hash=\(hash) url=\(manualOverrideURL.absoluteString)"
            )
            cache(url: manualOverrideURL, forHash: hash, titleCacheKey: titleCacheKey)
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: manualOverrideURL,
                provider: .manualTMDB,
                context: context
            )
            return manualOverrideURL
        }

        if let cachedTitleURL = cachedURL(for: titleCacheNamespaceKey(for: titleCacheKey)) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=title-cache hash=\(hash) titleCacheKey=\(titleCacheKey) url=\(cachedTitleURL.absoluteString)"
            )
            cache(url: cachedTitleURL, forHash: hash, titleCacheKey: titleCacheKey)
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: cachedTitleURL,
                provider: persistedMatchesByHash[hash]?.provider ?? .douban,
                context: context
            )
            return cachedTitleURL
        }

        if let cachedHashURL = cachedURL(for: hash) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=hash-cache hash=\(hash) url=\(cachedHashURL.absoluteString)"
            )
            return cachedHashURL
        }

        if let persisted = persistedMatchesByHash[hash] {
            if let persistedURL = persisted.posterURL {
                TransfersPosterDiagnostics.log(
                    "poster fetch hit source=persisted hash=\(hash) provider=\(persisted.provider.rawValue) url=\(persistedURL.absoluteString)"
                )
                cache(url: persistedURL, forHash: hash, titleCacheKey: persisted.titleCacheKey)
                return persistedURL
            }
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=persisted-negative hash=\(hash) provider=\(persisted.provider.rawValue)"
            )
            cacheNil(forHash: hash, titleCacheKey: persisted.titleCacheKey)
            return nil
        }

        let metadata = OiiQTParser.parse(name)
        TransfersPosterDiagnostics.log(
            "poster fetch metadata hash=\(hash) title=\(metadata.title) english=\(metadata.englishTitle ?? "nil") year=\(metadata.year ?? "nil")"
        )
        guard !metadata.title.isEmpty else {
            TransfersPosterDiagnostics.log("poster fetch skip reason=empty-title hash=\(hash)")
            persistMatch(hash: hash, titleCacheKey: titleCacheKey, posterURL: nil, provider: .none, context: context)
            cacheNil(forHash: hash, titleCacheKey: titleCacheKey)
            return nil
        }

        if let doubanURL = await resolveDoubanPosterURL(
            metadata: metadata,
            titleCacheKey: titleCacheKey,
            context: context
        ) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=douban hash=\(hash) url=\(doubanURL.absoluteString)"
            )
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: doubanURL,
                provider: .douban,
                context: context
            )
            cache(url: doubanURL, forHash: hash, titleCacheKey: titleCacheKey)
            return doubanURL
        }

        TransfersPosterDiagnostics.log("poster fetch miss source=douban hash=\(hash)")
        if let tmdbCustomURL = await TMDBService.shared.resolvePosterURL(for: metadata, using: .custom) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=tmdb-custom hash=\(hash) url=\(tmdbCustomURL.absoluteString)"
            )
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: tmdbCustomURL,
                provider: .tmdbCustom,
                context: context
            )
            cache(url: tmdbCustomURL, forHash: hash, titleCacheKey: titleCacheKey)
            return tmdbCustomURL
        }

        TransfersPosterDiagnostics.log("poster fetch miss source=tmdb-custom hash=\(hash)")
        if let tmdbBuiltInURL = await TMDBService.shared.resolvePosterURL(for: metadata, using: .builtIn) {
            TransfersPosterDiagnostics.log(
                "poster fetch hit source=tmdb-built-in hash=\(hash) url=\(tmdbBuiltInURL.absoluteString)"
            )
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: tmdbBuiltInURL,
                provider: .tmdbBuiltIn,
                context: context
            )
            cache(url: tmdbBuiltInURL, forHash: hash, titleCacheKey: titleCacheKey)
            return tmdbBuiltInURL
        }

        TransfersPosterDiagnostics.log("poster fetch miss source=tmdb-built-in hash=\(hash)")
        persistMatch(hash: hash, titleCacheKey: titleCacheKey, posterURL: nil, provider: .none, context: context)
        cacheNil(forHash: hash, titleCacheKey: titleCacheKey)
        TransfersPosterDiagnostics.log("poster fetch fail hash=\(hash) name=\(name)")
        return nil
    }

    func searchManualCandidates(
        query: String,
        tmdbPage: Int = 1
    ) async -> PosterSearchResultBatch {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return PosterSearchResultBatch(items: [], hasMoreTMDB: false)
        }

        async let doubanItems: [DoubanSuggestionItem] = tmdbPage == 1
            ? fetchDoubanSuggestions(query: trimmedQuery)
            : []
        async let tmdbItems = fetchTMDBManualCandidates(query: trimmedQuery, page: tmdbPage)

        let mappedDoubanItems = await doubanItems.map { suggestion in
            PosterSearchCandidate(
                id: "douban:\(suggestion.id)",
                source: .douban,
                title: suggestion.title,
                subtitle: suggestion.subtitle,
                year: suggestion.year,
                mediaType: suggestion.type,
                posterURL: URL(string: suggestion.normalizedPosterURLString),
                tmdbItem: nil,
                doubanID: suggestion.id
            )
        }
        let (tmdbResults, hasMoreTMDB) = await tmdbItems
        let mappedTMDBItems = tmdbResults.map { item in
            PosterSearchCandidate(
                id: "tmdb:\(item.id)",
                source: .tmdb,
                title: item.title,
                subtitle: item.overview ?? "",
                year: item.year,
                mediaType: item.mediaType,
                posterURL: item.fullPosterURL,
                tmdbItem: item,
                doubanID: nil
            )
        }

        let mergedItems = mergeManualCandidates(primary: mappedDoubanItems, secondary: mappedTMDBItems)
        return PosterSearchResultBatch(items: mergedItems, hasMoreTMDB: hasMoreTMDB)
    }

    func saveManualOverride(
        hash: String,
        name: String,
        candidate: PosterSearchCandidate,
        context: ModelContext
    ) {
        let titleCacheKey = cleanedTitleCacheKey(for: name)

        switch candidate.source {
        case .douban:
            guard let posterURL = candidate.posterURL else { return }
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: posterURL,
                provider: .manualDouban,
                context: context
            )
            cache(url: posterURL, forHash: hash, titleCacheKey: titleCacheKey)

        case .tmdb:
            guard let item = candidate.tmdbItem, let posterURL = candidate.posterURL else { return }
            TMDBService.shared.saveOverride(hash: hash, item: item, context: context)
            persistMatch(
                hash: hash,
                titleCacheKey: titleCacheKey,
                posterURL: posterURL,
                provider: .manualTMDB,
                context: context
            )
            cache(url: posterURL, forHash: hash, titleCacheKey: titleCacheKey)
        }
    }

    func clearCache(for hash: String, name: String? = nil) {
        urlCache.removeObject(forKey: hash as NSString)
        if let name {
            let titleCacheKey = cleanedTitleCacheKey(for: name)
            urlCache.removeObject(forKey: titleCacheNamespaceKey(for: titleCacheKey) as NSString)
        }
    }

    func clearPosterMatch(for hash: String, name: String? = nil, context: ModelContext) {
        clearCache(for: hash, name: name)
        persistedMatchesByHash.removeValue(forKey: hash)

        let descriptor = FetchDescriptor<PosterMatchRecord>(
            predicate: #Predicate { $0.hashString == hash }
        )
        if let matches = try? context.fetch(descriptor) {
            for match in matches {
                context.delete(match)
            }
        }

        if let name {
            clearPersistedDoubanLookups(titleCacheKey: cleanedTitleCacheKey(for: name), context: context)
        }

        TMDBService.shared.clearPosterMatch(for: hash, name: name, context: context)
        try? context.save()
    }

    private func hydratePersistedMatchesIfNeeded(context: ModelContext) {
        guard !hasHydratedPersistedMatches else { return }

        let descriptor = FetchDescriptor<PosterMatchRecord>()
        let matches = (try? context.fetch(descriptor)) ?? []
        persistedMatchesByHash = Dictionary(
            uniqueKeysWithValues: matches.map { ($0.hashString, PersistedPosterMatchRecord(record: $0)) }
        )
        hasHydratedPersistedMatches = true
    }

    private func hydratePersistedDoubanLookupsIfNeeded(context: ModelContext) {
        guard !hasHydratedPersistedDoubanLookups else { return }

        let descriptor = FetchDescriptor<DoubanPosterLookupRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        persistedDoubanLookupsByKey = Dictionary(
            uniqueKeysWithValues: records.map { ($0.lookupKey, PersistedDoubanLookupRecord(record: $0)) }
        )
        hasHydratedPersistedDoubanLookups = true
    }

    private func persistMatch(
        hash: String,
        titleCacheKey: String,
        posterURL: URL?,
        provider: PosterArtworkProvider,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<PosterMatchRecord>(
            predicate: #Predicate { $0.hashString == hash }
        )
        let existing = try? context.fetch(descriptor).first
        let record = existing ?? PosterMatchRecord(
            hashString: hash,
            titleCacheKey: titleCacheKey,
            posterURLString: posterURL?.absoluteString,
            providerRawValue: provider.rawValue
        )

        record.titleCacheKey = titleCacheKey
        record.posterURLString = posterURL?.absoluteString
        record.providerRawValue = provider.rawValue
        record.lastMatchedTime = Date()

        if existing == nil {
            context.insert(record)
        }

        persistedMatchesByHash[hash] = PersistedPosterMatchRecord(record: record)
        try? context.save()
    }

    private func persistDoubanLookup(
        candidate: DoubanLookupCandidate,
        posterURLString: String?,
        subjectID: String?,
        outcome: DoubanLookupOutcome,
        failureReason: String?,
        ttl: TimeInterval,
        context: ModelContext
    ) {
        let lookupKey = candidate.lookupKey
        let descriptor = FetchDescriptor<DoubanPosterLookupRecord>(
            predicate: #Predicate { $0.lookupKey == lookupKey }
        )
        let existing = try? context.fetch(descriptor).first
        let record = existing ?? DoubanPosterLookupRecord(
            lookupKey: lookupKey,
            titleCacheKey: candidate.titleCacheKey,
            queryValue: candidate.queryValue,
            targetYear: candidate.targetYear,
            mediaType: candidate.mediaType,
            posterURLString: posterURLString,
            subjectID: subjectID,
            outcomeRawValue: outcome.rawValue,
            failureReason: failureReason,
            validUntil: Date().addingTimeInterval(ttl)
        )

        record.titleCacheKey = candidate.titleCacheKey
        record.queryValue = candidate.queryValue
        record.targetYear = candidate.targetYear
        record.mediaType = candidate.mediaType
        record.posterURLString = posterURLString
        record.subjectID = subjectID
        record.outcomeRawValue = outcome.rawValue
        record.failureReason = failureReason
        record.validUntil = Date().addingTimeInterval(ttl)
        record.lastUpdatedAt = Date()

        if existing == nil {
            context.insert(record)
        }

        persistedDoubanLookupsByKey[lookupKey] = PersistedDoubanLookupRecord(record: record)
        try? context.save()
    }

    private func clearPersistedDoubanLookups(titleCacheKey: String, context: ModelContext) {
        let normalizedKey = titleCacheKey.lowercased()
        let descriptor = FetchDescriptor<DoubanPosterLookupRecord>(
            predicate: #Predicate { $0.titleCacheKey == normalizedKey }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        for record in records {
            persistedDoubanLookupsByKey.removeValue(forKey: record.lookupKey)
            context.delete(record)
        }
    }

    private func cachedURL(for cacheKey: String) -> URL? {
        guard let cachedValue = urlCache.object(forKey: cacheKey as NSString) as String? else {
            return nil
        }
        guard cachedValue != "null" else { return nil }
        return URL(string: cachedValue)
    }

    private func cache(url: URL, forHash hash: String, titleCacheKey: String) {
        let urlString = url.absoluteString as NSString
        urlCache.setObject(urlString, forKey: hash as NSString)
        urlCache.setObject(urlString, forKey: titleCacheNamespaceKey(for: titleCacheKey) as NSString)
    }

    private func cacheNil(forHash hash: String, titleCacheKey: String) {
        urlCache.setObject("null", forKey: hash as NSString)
        urlCache.setObject("null", forKey: titleCacheNamespaceKey(for: titleCacheKey) as NSString)
    }

    private func titleCacheNamespaceKey(for titleCacheKey: String) -> String {
        "poster::\(titleCacheKey.lowercased())"
    }

    private static let cleanCacheKeyRegex: NSRegularExpression? = {
        let pattern = "(?i)[\\.\\s_\\-\\[\\(]*(S\\d{2}(E\\d{2})?|(19|20)\\d{2}|2160p|1080p|720p|4k|WEB-DL|BluRay|x265|H265).*$"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private func cleanedTitleCacheKey(for rawName: String) -> String {
        guard let regex = Self.cleanCacheKeyRegex else { return rawName }
        let range = NSRange(rawName.startIndex..., in: rawName)
        let cleaned = regex.stringByReplacingMatches(in: rawName, options: [], range: range, withTemplate: "")
        let finalTitle = cleaned
            .trimmingCharacters(in: CharacterSet(charactersIn: ". _-[]()"))
            .trimmingCharacters(in: .whitespaces)
        return finalTitle.isEmpty ? rawName : finalTitle
    }

    private func resolveDoubanPosterURL(
        metadata: OiiQTMetadata,
        titleCacheKey: String,
        context: ModelContext
    ) async -> URL? {
        let candidates = doubanLookupCandidates(for: metadata, titleCacheKey: titleCacheKey)
        var pendingCandidates: [DoubanLookupCandidate] = []

        for candidate in candidates {
            if let persisted = persistedDoubanLookupsByKey[candidate.lookupKey], persisted.isValid {
                TransfersPosterDiagnostics.log(
                    "douban lookup hit source=persisted key=\(candidate.lookupKey) outcome=\(persisted.outcome.rawValue)"
                )
                if let posterURL = persisted.posterURL {
                    return posterURL
                }
                continue
            }
            pendingCandidates.append(candidate)
        }

        guard canAttemptDoubanRequest() else {
            let cooldownText = doubanSuppressedUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
            TransfersPosterDiagnostics.log(
                "douban search skip reason=suppressed-until value=\(cooldownText)"
            )
            return nil
        }

        for candidate in pendingCandidates {
            let result = await fetchDoubanSuggestionsResult(query: candidate.queryValue)
            switch result {
            case .success(let items):
                TransfersPosterDiagnostics.log(
                    "douban search finish key=\(candidate.lookupKey) query=\(candidate.queryValue) results=\(items.count)"
                )
                if let best = selectBestDoubanSuggestion(from: items, metadata: metadata) {
                    let posterURLString = best.normalizedPosterURLString
                    persistDoubanLookup(
                        candidate: candidate,
                        posterURLString: posterURLString,
                        subjectID: best.id,
                        outcome: .success,
                        failureReason: nil,
                        ttl: Self.doubanSuccessLookupTTL,
                        context: context
                    )
                    return URL(string: posterURLString)
                }
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .negative,
                    failureReason: nil,
                    ttl: Self.doubanNegativeLookupTTL,
                    context: context
                )
            case .negative:
                TransfersPosterDiagnostics.log(
                    "douban search finish key=\(candidate.lookupKey) query=\(candidate.queryValue) results=0"
                )
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .negative,
                    failureReason: nil,
                    ttl: Self.doubanNegativeLookupTTL,
                    context: context
                )
            case .rateLimited(let reason):
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .rateLimited,
                    failureReason: reason,
                    ttl: Self.doubanRateLimitLookupTTL,
                    context: context
                )
            case .timeout:
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .timeout,
                    failureReason: result.failureReason,
                    ttl: Self.doubanNetworkLookupTTL,
                    context: context
                )
            case .decodeFailure:
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .decodeFailure,
                    failureReason: result.failureReason,
                    ttl: Self.doubanDecodeLookupTTL,
                    context: context
                )
            case .networkError(let reason):
                persistDoubanLookup(
                    candidate: candidate,
                    posterURLString: nil,
                    subjectID: nil,
                    outcome: .networkError,
                    failureReason: reason,
                    ttl: Self.doubanNetworkLookupTTL,
                    context: context
                )
            }
        }

        return nil
    }

    private func doubanLookupCandidates(
        for metadata: OiiQTMetadata,
        titleCacheKey: String
    ) -> [DoubanLookupCandidate] {
        let normalizedTitleCacheKey = titleCacheKey.lowercased()
        let mediaType = inferredDoubanMediaType(for: metadata)
        var candidates: [DoubanLookupCandidate] = [
            DoubanLookupCandidate(
                lookupKey: doubanLookupKey(
                    titleCacheKey: normalizedTitleCacheKey,
                    query: metadata.title,
                    targetYear: metadata.year,
                    mediaType: mediaType
                ),
                titleCacheKey: normalizedTitleCacheKey,
                queryValue: metadata.title,
                targetYear: metadata.year,
                mediaType: mediaType
            )
        ]

        if let englishTitle = metadata.englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !englishTitle.isEmpty,
           englishTitle.caseInsensitiveCompare(metadata.title) != .orderedSame {
            candidates.append(
                DoubanLookupCandidate(
                    lookupKey: doubanLookupKey(
                        titleCacheKey: normalizedTitleCacheKey,
                        query: englishTitle,
                        targetYear: metadata.year,
                        mediaType: mediaType
                    ),
                    titleCacheKey: normalizedTitleCacheKey,
                    queryValue: englishTitle,
                    targetYear: metadata.year,
                    mediaType: mediaType
                )
            )
        }

        return candidates
    }

    private func doubanLookupKey(
        titleCacheKey: String,
        query: String,
        targetYear: String?,
        mediaType: String
    ) -> String {
        let normalizedQuery = normalizeDoubanTitle(query)
        let normalizedYear = targetYear?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "na"
        return "douban::\(titleCacheKey)::\(normalizedQuery)::\(normalizedYear)::\(mediaType)"
    }

    private func inferredDoubanMediaType(for metadata: OiiQTMetadata) -> String {
        metadata.season != nil ? "tv" : "movie"
    }

    private func fetchTMDBManualCandidates(
        query: String,
        page: Int
    ) async -> ([TMDBItem], Bool) {
        let customItems = await TMDBService.shared.search(
            query: query,
            page: page,
            apiKeySource: .custom
        )
        let items = customItems.isEmpty
            ? await TMDBService.shared.search(
                query: query,
                page: page,
                apiKeySource: .builtIn
            )
            : customItems
        return (items, items.count >= 20)
    }

    private func fetchDoubanSuggestions(query: String) async -> [DoubanSuggestionItem] {
        let result = await fetchDoubanSuggestionsResult(query: query)
        switch result {
        case .success(let items):
            return items
        case .negative, .rateLimited, .timeout, .decodeFailure, .networkError:
            return []
        }
    }

    private func fetchDoubanSuggestionsResult(query: String) async -> DoubanSuggestionFetchResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return .negative }
        guard canAttemptDoubanRequest() else { return .rateLimited("suppressed") }

        let lookup = await doubanSearchCoordinator.cachedOrTask(for: normalizedQuery.lowercased()) {
            let coordinator = self.doubanSearchCoordinator
            let cacheKey = normalizedQuery.lowercased()
            return Task {
                await coordinator.acquirePermit()
                let outcome = await DoubanRequestClient.shared.fetchSuggestions(query: normalizedQuery)
                let cacheableResults: [DoubanSuggestionItem]
                let isCacheable: Bool
                switch outcome {
                case .success(let items):
                    cacheableResults = items
                    isCacheable = true
                case .negative:
                    cacheableResults = []
                    isCacheable = true
                case .rateLimited, .timeout, .decodeFailure, .networkError:
                    cacheableResults = []
                    isCacheable = false
                }
                await coordinator.completeRequest(for: cacheKey, result: cacheableResults, cacheable: isCacheable)
                return outcome
            }
        }

        switch lookup {
        case .cached(let items):
            return items.isEmpty ? .negative : .success(items)
        case .task(let task):
            let outcome = await task.value
            switch outcome {
            case .success, .negative:
                recordDoubanHealthyResponse()
            case .rateLimited(let reason):
                recordDoubanFailure(outcome: .rateLimited, reason: reason)
            case .timeout:
                recordDoubanFailure(outcome: .timeout, reason: outcome.failureReason ?? "timeout")
            case .decodeFailure:
                recordDoubanFailure(outcome: .decodeFailure, reason: outcome.failureReason ?? "decode-failure")
            case .networkError(let reason):
                recordDoubanFailure(outcome: .networkError, reason: reason)
            }
            return outcome
        }
    }

    private func selectBestDoubanSuggestion(
        from items: [DoubanSuggestionItem],
        metadata: OiiQTMetadata
    ) -> DoubanSuggestionItem? {
        guard !items.isEmpty else { return nil }

        let targetYear = metadata.year.flatMap(Int.init)
        let normalizedPrimaryTitle = normalizeDoubanTitle(metadata.title)
        let normalizedEnglishTitle = metadata.englishTitle.map(normalizeDoubanTitle)

        var bestItem: DoubanSuggestionItem?
        var bestScore = Int.min

        for (index, item) in items.enumerated() {
            var score = 0

            let normalizedTitle = normalizeDoubanTitle(item.title)
            let normalizedSubtitle = normalizeDoubanTitle(item.subtitle)

            if normalizedTitle == normalizedPrimaryTitle {
                score += 120
            } else if normalizedTitle.contains(normalizedPrimaryTitle) || normalizedPrimaryTitle.contains(normalizedTitle) {
                score += 80
            }

            if let normalizedEnglishTitle, !normalizedEnglishTitle.isEmpty {
                if normalizedSubtitle == normalizedEnglishTitle {
                    score += 100
                } else if normalizedSubtitle.contains(normalizedEnglishTitle) || normalizedEnglishTitle.contains(normalizedSubtitle) {
                    score += 60
                }
            }

            if let targetYear, let itemYear = Int(item.year) {
                if itemYear == targetYear {
                    score += 100
                } else if abs(itemYear - targetYear) <= 1 {
                    score += 50
                }
            }

            if item.type == "tv" && metadata.season != nil {
                score += 20
            }

            score += max(0, 10 - index)

            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }

        return bestItem
    }

    private func normalizeDoubanTitle(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canAttemptDoubanRequest() -> Bool {
        guard let doubanSuppressedUntil else { return true }
        if doubanSuppressedUntil <= Date() {
            self.doubanSuppressedUntil = nil
            self.doubanFailureStreak = max(0, doubanFailureStreak - 1)
            return true
        }
        return false
    }

    private func recordDoubanHealthyResponse() {
        guard doubanFailureStreak > 0 || doubanSuppressedUntil != nil else { return }
        doubanFailureStreak = max(0, doubanFailureStreak - 1)
        if doubanFailureStreak == 0 {
            doubanSuppressedUntil = nil
        }
    }

    private func recordDoubanFailure(outcome: DoubanLookupOutcome, reason: String) {
        let baseInterval: TimeInterval
        switch outcome {
        case .rateLimited:
            baseInterval = 30
        case .networkError, .timeout:
            baseInterval = 15
        case .decodeFailure:
            baseInterval = 45
        case .success, .negative:
            return
        }

        doubanFailureStreak += 1
        TransfersPosterDiagnostics.log(
            "douban failure count=\(doubanFailureStreak) outcome=\(outcome.rawValue) reason=\(reason)"
        )
        let exponent = min(max(doubanFailureStreak - 1, 0), 4)
        let suppressionInterval = min(
            baseInterval * pow(2.0, Double(exponent)),
            Self.doubanMaxSuppressionInterval
        )
        let cooldownUntil = Date().addingTimeInterval(max(Self.doubanBaseSuppressionInterval, suppressionInterval))
        doubanSuppressedUntil = cooldownUntil
        TransfersPosterDiagnostics.log(
            "douban circuit open until=\(ISO8601DateFormatter().string(from: cooldownUntil))"
        )
    }

    private func mergeManualCandidates(
        primary: [PosterSearchCandidate],
        secondary: [PosterSearchCandidate]
    ) -> [PosterSearchCandidate] {
        var seenKeys = Set<String>()
        var merged: [PosterSearchCandidate] = []

        for item in primary + secondary {
            let dedupeKey = "\(normalizeDoubanTitle(item.title))|\(item.year)"
            guard seenKeys.insert(dedupeKey).inserted else { continue }
            merged.append(item)
        }

        return merged
    }
}

private struct PersistedPosterMatchRecord {
    let hashString: String
    let titleCacheKey: String
    let posterURLString: String?
    let provider: PosterArtworkProvider

    var isManualOverride: Bool {
        provider == .manualTMDB || provider == .manualDouban
    }

    var posterURL: URL? {
        guard let posterURLString else { return nil }
        return URL(string: posterURLString)
    }

    init(record: PosterMatchRecord) {
        self.hashString = record.hashString
        self.titleCacheKey = record.titleCacheKey
        self.posterURLString = record.posterURLString
        self.provider = PosterArtworkProvider(rawValue: record.providerRawValue) ?? .none
    }
}

private struct PersistedDoubanLookupRecord {
    let lookupKey: String
    let titleCacheKey: String
    let posterURLString: String?
    let subjectID: String?
    let outcome: DoubanLookupOutcome
    let failureReason: String?
    let validUntil: Date

    var posterURL: URL? {
        guard let posterURLString else { return nil }
        return URL(string: posterURLString)
    }

    var isValid: Bool {
        validUntil > Date()
    }

    init(record: DoubanPosterLookupRecord) {
        self.lookupKey = record.lookupKey
        self.titleCacheKey = record.titleCacheKey
        self.posterURLString = record.posterURLString
        self.subjectID = record.subjectID
        self.outcome = DoubanLookupOutcome(rawValue: record.outcomeRawValue) ?? .negative
        self.failureReason = record.failureReason
        self.validUntil = record.validUntil
    }
}

private enum DoubanLookupOutcome: String {
    case success
    case negative
    case rateLimited = "rate_limited"
    case networkError = "network_error"
    case timeout
    case decodeFailure = "decode_failure"
}

private struct DoubanLookupCandidate {
    let lookupKey: String
    let titleCacheKey: String
    let queryValue: String
    let targetYear: String?
    let mediaType: String
}

struct DoubanSuggestionResponseItem: Decodable, Sendable {
    let episode: String?
    let img: String?
    let title: String
    let url: String?
    let type: String
    let year: String
    let subTitle: String?
    let id: String

    enum CodingKeys: String, CodingKey {
        case episode
        case img
        case title
        case url
        case type
        case year
        case subTitle = "sub_title"
        case id
    }
}

struct DoubanSuggestionItem: Sendable {
    let title: String
    let subtitle: String
    let year: String
    let type: String
    let posterURLString: String
    let id: String

    nonisolated var normalizedPosterURLString: String {
        DoubanImageURLNormalizer.normalize(posterURLString)
    }

    nonisolated init(response: DoubanSuggestionResponseItem) {
        self.title = response.title
        self.subtitle = response.subTitle ?? ""
        self.year = response.year
        self.type = response.type
        self.posterURLString = response.img ?? ""
        self.id = response.id
    }
}

struct PosterSearchResultBatch: Sendable {
    let items: [PosterSearchCandidate]
    let hasMoreTMDB: Bool
}

struct PosterSearchCandidate: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case douban
        case tmdb
    }

    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let year: String
    let mediaType: String
    let posterURL: URL?
    let tmdbItem: TMDBItem?
    let doubanID: String?

    var sourceLabel: String {
        switch source {
        case .douban:
            return "豆瓣"
        case .tmdb:
            return "TMDB"
        }
    }

    var typeLabel: String {
        mediaType == "tv"
            ? LanguageManager.shared.localized("TV Series")
            : LanguageManager.shared.localized("Movie")
    }
}

private actor DoubanPosterSearchCoordinator {
    enum Lookup {
        case cached([DoubanSuggestionItem])
        case task(Task<DoubanSuggestionFetchResult, Never>)
    }

    private let maxConcurrentRequests: Int
    private let maxCachedEntries: Int
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cachedResults: [String: [DoubanSuggestionItem]] = [:]
    private var cacheOrder: [String] = []
    private var inFlightTasks: [String: Task<DoubanSuggestionFetchResult, Never>] = [:]

    init(maxConcurrentRequests: Int, maxCachedEntries: Int) {
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
        self.maxCachedEntries = max(16, maxCachedEntries)
    }

    func cachedOrTask(
        for cacheKey: String,
        makeTask: @escaping @Sendable () -> Task<DoubanSuggestionFetchResult, Never>
    ) -> Lookup {
        if let cached = cachedResults[cacheKey] {
            touch(cacheKey)
            return .cached(cached)
        }
        if let existing = inFlightTasks[cacheKey] {
            return .task(existing)
        }
        let task = makeTask()
        inFlightTasks[cacheKey] = task
        return .task(task)
    }

    func acquirePermit() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func completeRequest(for cacheKey: String, result: [DoubanSuggestionItem], cacheable: Bool) {
        if cacheable {
            cachedResults[cacheKey] = result
            touch(cacheKey)
            evictIfNeeded()
        }
        inFlightTasks[cacheKey] = nil
        releasePermit()
    }

    private func touch(_ cacheKey: String) {
        cacheOrder.removeAll(where: { $0 == cacheKey })
        cacheOrder.append(cacheKey)
    }

    private func evictIfNeeded() {
        while cacheOrder.count > maxCachedEntries {
            let oldestKey = cacheOrder.removeFirst()
            cachedResults.removeValue(forKey: oldestKey)
        }
    }

    private func releasePermit() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            return
        }
        activeRequests = max(0, activeRequests - 1)
    }
}

#if DEBUG
private struct PosterReliabilityVerificationResult {
    let id: String
    let passed: Bool
    let detail: String
}

extension PosterArtworkService {
    nonisolated static var isReliabilityVerificationRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-OiiQTPosterReliabilityVerification")
    }

    @MainActor
    static func runReliabilityVerification() async -> Bool {
        let results = [
            await verifyPersistedLookupReuse(),
            await verifyRateLimitedShortCircuit(),
            await verifyProxyRouting()
        ]

        for result in results {
            let status = result.passed ? "PASS" : "FAIL"
            print("[PosterReliabilityVerification] \(result.id): \(status) - \(result.detail)")
        }

        let overallPassed = results.allSatisfy(\.passed)
        print("[PosterReliabilityVerification] overall: \(overallPassed ? "PASS" : "FAIL")")
        return overallPassed
    }

    @MainActor
    private static func verifyPersistedLookupReuse() async -> PosterReliabilityVerificationResult {
        do {
            let (_, context) = try makeVerificationStore(name: "persisted-reuse")
            let firstService = PosterArtworkService()
            let sampleName = "The.Matrix.1999.1080p.BluRay.x265"
            let metadata = OiiQTParser.parse(sampleName)
            let titleCacheKey = firstService.cleanedTitleCacheKey(for: sampleName)
            let candidate = try requireCandidate(from: firstService.doubanLookupCandidates(for: metadata, titleCacheKey: titleCacheKey))
            let expectedURLString = "https://img9.doubanio.com/view/photo/s_ratio_poster/public/p480747492.webp"

            firstService.persistDoubanLookup(
                candidate: candidate,
                posterURLString: expectedURLString,
                subjectID: "1291843",
                outcome: .success,
                failureReason: nil,
                ttl: Self.doubanSuccessLookupTTL,
                context: context
            )

            let secondService = PosterArtworkService()
            secondService.preparePosterCacheIfNeeded(context: context)
            secondService.doubanSuppressedUntil = Date().addingTimeInterval(300)

            let resolvedURL = await secondService.resolveDoubanPosterURL(
                metadata: metadata,
                titleCacheKey: titleCacheKey,
                context: context
            )

            let passed = resolvedURL?.absoluteString == expectedURLString
            return PosterReliabilityVerificationResult(
                id: "5.1",
                passed: passed,
                detail: passed
                    ? "fresh service instance reused persisted Douban lookup"
                    : "expected persisted URL \(expectedURLString), got \(resolvedURL?.absoluteString ?? "nil")"
            )
        } catch {
            return PosterReliabilityVerificationResult(
                id: "5.1",
                passed: false,
                detail: "verification threw \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private static func verifyRateLimitedShortCircuit() async -> PosterReliabilityVerificationResult {
        do {
            let (_, context) = try makeVerificationStore(name: "rate-limit-short-circuit")
            let service = PosterArtworkService()
            let sampleName = "Severance.S02E01.2025.1080p.WEB-DL"
            let metadata = OiiQTParser.parse(sampleName)
            let titleCacheKey = service.cleanedTitleCacheKey(for: sampleName)

            service.preparePosterCacheIfNeeded(context: context)
            service.recordDoubanFailure(outcome: .rateLimited, reason: "http-429")

            let start = DispatchTime.now().uptimeNanoseconds
            let resolvedURL = await service.resolveDoubanPosterURL(
                metadata: metadata,
                titleCacheKey: titleCacheKey,
                context: context
            )
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let passed = resolvedURL == nil && elapsedMs < 50
            let detail = passed
                ? String(format: "suppressed Douban path returned nil in %.2f ms", elapsedMs)
                : String(format: "expected quick nil under suppression, got %@ in %.2f ms", resolvedURL?.absoluteString ?? "nil", elapsedMs)

            return PosterReliabilityVerificationResult(
                id: "5.2",
                passed: passed,
                detail: detail
            )
        } catch {
            return PosterReliabilityVerificationResult(
                id: "5.2",
                passed: false,
                detail: "verification threw \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private static func verifyProxyRouting() async -> PosterReliabilityVerificationResult {
        let defaults = UserDefaults.standard
        let previousSearchProxy = defaults.string(forKey: DoubanNetworkRouting.searchProxyUserDefaultsKey)
        let previousImageProxy = defaults.string(forKey: DoubanNetworkRouting.imageProxyUserDefaultsKey)

        defer {
            if let previousSearchProxy {
                defaults.set(previousSearchProxy, forKey: DoubanNetworkRouting.searchProxyUserDefaultsKey)
            } else {
                defaults.removeObject(forKey: DoubanNetworkRouting.searchProxyUserDefaultsKey)
            }

            if let previousImageProxy {
                defaults.set(previousImageProxy, forKey: DoubanNetworkRouting.imageProxyUserDefaultsKey)
            } else {
                defaults.removeObject(forKey: DoubanNetworkRouting.imageProxyUserDefaultsKey)
            }
        }

        defaults.removeObject(forKey: DoubanNetworkRouting.searchProxyUserDefaultsKey)
        defaults.removeObject(forKey: DoubanNetworkRouting.imageProxyUserDefaultsKey)

        let originalImageURL = URL(string: "https://img9.doubanio.com/view/photo/s_ratio_poster/public/p480747492.webp")!
        let directSearchURL = DoubanNetworkRouting.searchRequestURL(query: "matrix")
        let directImageURL = DoubanNetworkRouting.routedImageURL(for: originalImageURL)

        defaults.set("https://proxy.example.com/douban/search", forKey: DoubanNetworkRouting.searchProxyUserDefaultsKey)
        defaults.set("https://proxy.example.com/douban/image", forKey: DoubanNetworkRouting.imageProxyUserDefaultsKey)

        let proxiedSearchURL = DoubanNetworkRouting.searchRequestURL(query: "matrix")
        let proxiedImageURL = DoubanNetworkRouting.routedImageURL(for: originalImageURL)
        let proxiedSearchQuery = URLComponents(url: proxiedSearchURL ?? originalImageURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" })?
            .value
        let proxiedImageQuery = URLComponents(url: proxiedImageURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "imgurl" })?
            .value

        let directSearchIsDirect = directSearchURL?.host?.contains("douban.com") == true
        let directImageIsInert = directImageURL == originalImageURL
        let proxiedSearchWorks = proxiedSearchURL?.host == "proxy.example.com"
            && proxiedSearchURL?.path == "/douban/search"
            && proxiedSearchQuery == "matrix"
        let proxiedImageWorks = proxiedImageURL.host == "proxy.example.com"
            && proxiedImageURL.path == "/douban/image"
            && proxiedImageQuery == originalImageURL.absoluteString
        let passed = directSearchIsDirect && directImageIsInert && proxiedSearchWorks && proxiedImageWorks

        return PosterReliabilityVerificationResult(
            id: "5.3",
            passed: passed,
            detail: passed
                ? "direct routing stayed inert and configured proxies rewrote search/image URLs"
                : "directSearch=\(directSearchURL?.absoluteString ?? "nil"), directImage=\(directImageURL.absoluteString), proxiedSearch=\(proxiedSearchURL?.absoluteString ?? "nil"), proxiedImage=\(proxiedImageURL.absoluteString)"
        )
    }

    @MainActor
    private static func makeVerificationStore(name: String) throws -> (URL, ModelContext) {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oiiqt-poster-verification-\(name)-\(UUID().uuidString).sqlite")
        let schema = Schema([
            PosterMatchRecord.self,
            DoubanPosterLookupRecord.self,
            TMDBMatch.self
        ])
        let configuration = ModelConfiguration(
            "PosterReliability-\(name)",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        return (storeURL, context)
    }

    @MainActor
    private static func requireCandidate(from candidates: [DoubanLookupCandidate]) throws -> DoubanLookupCandidate {
        guard let first = candidates.first else {
            throw NSError(domain: "PosterReliabilityVerification", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "missing Douban lookup candidate"
            ])
        }
        return first
    }
}
#endif
