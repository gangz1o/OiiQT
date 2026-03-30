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
    fileprivate enum DoubanRequestOutcome {
        case success([DoubanSuggestionItem])
        case failure(String)
    }

    static let shared = PosterArtworkService()
    private static let doubanFailureThreshold = 2
    private static let doubanCooldownInterval: TimeInterval = 180
    private static let doubanRequestTimeout: TimeInterval = 2.5

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
    private var consecutiveDoubanFailures = 0
    private var doubanCooldownUntil: Date?

    private init() {}

    func cachedPosterURL(for hash: String) -> URL? {
        cachedURL(for: hash)
    }

    func preparePosterCacheIfNeeded(context: ModelContext) {
        hydratePersistedMatchesIfNeeded(context: context)
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

        if let doubanURL = await resolveDoubanPosterURL(metadata: metadata) {
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

    private func resolveDoubanPosterURL(metadata: OiiQTMetadata) async -> URL? {
        guard canAttemptDoubanRequest() else {
            let cooldownText = doubanCooldownUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
            TransfersPosterDiagnostics.log(
                "douban search skip reason=cooldown-until value=\(cooldownText)"
            )
            return nil
        }

        let primaryResults = await fetchDoubanSuggestions(query: metadata.title)
        TransfersPosterDiagnostics.log(
            "douban search primary title=\(metadata.title) year=\(metadata.year ?? "nil") results=\(primaryResults.count)"
        )
        if let bestPrimary = selectBestDoubanSuggestion(from: primaryResults, metadata: metadata) {
            return URL(string: bestPrimary.normalizedPosterURLString)
        }

        if let englishTitle = metadata.englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !englishTitle.isEmpty,
           englishTitle.caseInsensitiveCompare(metadata.title) != .orderedSame {
            let fallbackResults = await fetchDoubanSuggestions(query: englishTitle)
            TransfersPosterDiagnostics.log(
                "douban search fallback title=\(englishTitle) year=\(metadata.year ?? "nil") results=\(fallbackResults.count)"
            )
            if let bestFallback = selectBestDoubanSuggestion(from: fallbackResults, metadata: metadata) {
                return URL(string: bestFallback.normalizedPosterURLString)
            }
        }

        return nil
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
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        guard canAttemptDoubanRequest() else { return [] }

        let lookup = await doubanSearchCoordinator.cachedOrTask(for: normalizedQuery.lowercased()) {
            let coordinator = self.doubanSearchCoordinator
            let cacheKey = normalizedQuery.lowercased()
            return Task {
                await coordinator.acquirePermit()
                let outcome = await Self.performDoubanSuggestionRequest(query: normalizedQuery)
                let cacheableResults: [DoubanSuggestionItem]
                let isCacheable: Bool
                switch outcome {
                case .success(let items):
                    cacheableResults = items
                    isCacheable = true
                case .failure:
                    cacheableResults = []
                    isCacheable = false
                }
                await coordinator.completeRequest(for: cacheKey, result: cacheableResults, cacheable: isCacheable)
                return outcome
            }
        }

        switch lookup {
        case .cached(let items):
            return items
        case .task(let task):
            let outcome = await task.value
            switch outcome {
            case .success(let items):
                resetDoubanFailureState()
                return items
            case .failure(let reason):
                recordDoubanFailure(reason: reason)
                return []
            }
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
        guard let doubanCooldownUntil else { return true }
        if doubanCooldownUntil <= Date() {
            self.doubanCooldownUntil = nil
            self.consecutiveDoubanFailures = 0
            return true
        }
        return false
    }

    private func resetDoubanFailureState() {
        consecutiveDoubanFailures = 0
        doubanCooldownUntil = nil
    }

    private func recordDoubanFailure(reason: String) {
        consecutiveDoubanFailures += 1
        TransfersPosterDiagnostics.log(
            "douban failure count=\(consecutiveDoubanFailures) threshold=\(Self.doubanFailureThreshold) reason=\(reason)"
        )
        guard consecutiveDoubanFailures >= Self.doubanFailureThreshold else { return }
        let cooldownUntil = Date().addingTimeInterval(Self.doubanCooldownInterval)
        doubanCooldownUntil = cooldownUntil
        TransfersPosterDiagnostics.log(
            "douban circuit open until=\(ISO8601DateFormatter().string(from: cooldownUntil))"
        )
    }

    private static func performDoubanSuggestionRequest(query: String) async -> DoubanRequestOutcome {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://movie.douban.com/j/subject_suggest?q=\(encodedQuery)") else {
            return .failure("bad-url")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = Self.doubanRequestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                TransfersPosterDiagnostics.log(
                    "douban request error query=\(query) status=\(httpResponse.statusCode)"
                )
                return .failure("http-\(httpResponse.statusCode)")
            }
            let decoder = JSONDecoder()
            guard let decoded = try? decoder.decode([DoubanSuggestionResponseItem].self, from: data).map(DoubanSuggestionItem.init) else {
                TransfersPosterDiagnostics.log(
                    "douban request error query=\(query) reason=decode-failed bytes=\(data.count)"
                )
                return .failure("decode-failed")
            }
            TransfersPosterDiagnostics.log(
                "douban request finish query=\(query) results=\(decoded.count)"
            )
            return .success(decoded)
        } catch {
            TransfersPosterDiagnostics.log(
                "douban request error query=\(query) error=\(error.localizedDescription)"
            )
            return .failure(error.localizedDescription)
        }
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

private struct DoubanSuggestionResponseItem: Decodable, Sendable {
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

private struct DoubanSuggestionItem: Sendable {
    let title: String
    let subtitle: String
    let year: String
    let type: String
    let posterURLString: String
    let id: String

    var normalizedPosterURLString: String {
        DoubanImageURLNormalizer.normalize(posterURLString)
    }

    init(response: DoubanSuggestionResponseItem) {
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
        case task(Task<PosterArtworkService.DoubanRequestOutcome, Never>)
    }

    private let maxConcurrentRequests: Int
    private let maxCachedEntries: Int
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cachedResults: [String: [DoubanSuggestionItem]] = [:]
    private var cacheOrder: [String] = []
    private var inFlightTasks: [String: Task<PosterArtworkService.DoubanRequestOutcome, Never>] = [:]

    init(maxConcurrentRequests: Int, maxCachedEntries: Int) {
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
        self.maxCachedEntries = max(16, maxCachedEntries)
    }

    func cachedOrTask(
        for cacheKey: String,
        makeTask: @escaping @Sendable () -> Task<PosterArtworkService.DoubanRequestOutcome, Never>
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
