//
//  TMDBService.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/14.
//

import Foundation
import SwiftUI

import SwiftData

enum TMDBAPIKeySource: String, Sendable {
    case `default`
    case custom
    case builtIn
}

class TMDBService {
    static let shared = TMDBService()

    // MARK: - Configuration
    // 此功能仅供 Pro 付费用户开启
    private let builtInAPIKey = "24c4e7a516af276925d44ac5cc90a59f"
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p/w300"
    private let overridesKey = "tmdb_overrides"

    // MARK: - Caching
    // Memory Cache for Hash -> PosterURLString (NOT Image data, just mapping)
    // Image data is handled by Kingfisher
    private let urlCache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 5_000   // max 5K hash→path entries (~400 KB)
        return c
    }()
    private let searchCoordinator = TMDBSearchCoordinator(maxConcurrentRequests: 4, maxCachedEntries: 160)

    // Legacy UserDefaults (for migration)
    private var legacyOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overridesKey) }
    }

    private var customAPIKey: String? {
        guard UserDefaults.standard.bool(forKey: "isProUser") else { return nil }
        let customKey = (UserDefaults.standard.string(forKey: "customTMDBApiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return customKey.isEmpty ? nil : customKey
    }

    private var apiKeyToUse: String {
        customAPIKey ?? builtInAPIKey
    }

    private let isVerboseLoggingEnabled = false
    private var persistedPosterMatchesByHash: [String: PersistedPosterMatch] = [:]
    private var hasHydratedPersistedPosterMatches = false

    private init() {}

    // MARK: - Public API

    /// Fast, synchronous cache-only poster lookup (no I/O).
    /// Returns the poster URL if it's already in the in-memory cache; nil otherwise.
    func cachedPosterURL(for hash: String) -> URL? {
        let scopedHash = scopedHash(for: hash)
        if let cachedPath = urlCache.object(forKey: scopedHash as NSString) as String?,
           cachedPath != "null" {
            return URL(string: imageBaseURL + cachedPath)
        }
        return nil
    }

    /// 根据种子获取海报 URL
    /// - Parameters:
    ///   - hash: 种子 Hash (ID)
    ///   - name: 种子名称 (用于搜索)
    ///   - context: SwiftData Context (from View)
    @MainActor
    func preparePosterCacheIfNeeded(context: ModelContext) {
        hydratePersistedPosterMatchesIfNeeded(context: context)
    }

    @MainActor
    func manualOverridePosterURL(for hash: String, context: ModelContext) -> URL? {
        hydratePersistedPosterMatchesIfNeeded(context: context)

        let scopedHash = scopedHash(for: hash)
        if let persistedMatch = persistedPosterMatchesByHash[scopedHash],
           persistedMatch.isManualOverride,
           let path = persistedMatch.posterPath {
            return URL(string: imageBaseURL + path)
        }

        if let legacyMatch = persistedPosterMatchesByHash[hash],
           legacyMatch.isManualOverride,
           let path = legacyMatch.posterPath {
            return URL(string: imageBaseURL + path)
        }

        if let legacyPath = legacyOverrides[hash] {
            return URL(string: imageBaseURL + legacyPath)
        }

        return nil
    }

    func resolvePosterURL(for metadata: OiiQTMetadata, using apiKeySource: TMDBAPIKeySource) async -> URL? {
        guard !metadata.title.isEmpty,
              let posterPath = await searchBestMatch(metadata: metadata, apiKeySource: apiKeySource) else {
            return nil
        }
        return URL(string: imageBaseURL + posterPath)
    }

    @MainActor
    func fetchPoster(hash: String, name: String, context: ModelContext) async -> URL? {
        let scopedHash = scopedHash(for: hash)
        let cacheKey = extractCleanCacheKey(from: name)
        let scopedCacheKey = scopedPosterCacheKey(for: cacheKey)
        let startUptime = DispatchTime.now().uptimeNanoseconds
        TransfersPosterDiagnostics.log(
            "tmdb fetch start hash=\(scopedHash) cacheKey=\(cacheKey) name=\(name)"
        )

        // 1. Check shared clean-title memory cache first (fast path — no SwiftData)
        if let cachedPath = urlCache.object(forKey: scopedCacheKey as NSString) as String? {
            if cachedPath == "null" {
                TransfersPosterDiagnostics.log("tmdb fetch hit source=title-memory-negative hash=\(scopedHash)")
                return nil  // negative cache: skip SwiftData to avoid main-thread I/O during scroll
            }
            cacheURL(cachedPath, for: scopedHash)
            TransfersPosterDiagnostics.log("tmdb fetch hit source=title-memory hash=\(scopedHash) path=\(cachedPath)")
            return URL(string: imageBaseURL + cachedPath)
        }

        // 2. Check per-hash memory cache (fast path — no SwiftData)
        if let cachedPath = urlCache.object(forKey: scopedHash as NSString) as String? {
            if cachedPath == "null" {
                TransfersPosterDiagnostics.log("tmdb fetch hit source=hash-memory-negative hash=\(scopedHash)")
                return nil  // negative cache: skip SwiftData to avoid main-thread I/O during scroll
            }
            cacheURL(cachedPath, for: scopedCacheKey)
            TransfersPosterDiagnostics.log("tmdb fetch hit source=hash-memory hash=\(scopedHash) path=\(cachedPath)")
            return URL(string: imageBaseURL + cachedPath)
        }

        hydratePersistedPosterMatchesIfNeeded(context: context)

        // 2. data persistence snapshot (SwiftData -> in-memory lookup)
        if let persistedMatch = persistedPosterMatchesByHash[scopedHash] {
            if let path = persistedMatch.posterPath {
                cacheURL(path, for: scopedHash)
                cacheURL(path, for: scopedCacheKey)
                log("[TMDB] fetchPoster: SwiftData HIT for '\(name)' → \(path)")
                TransfersPosterDiagnostics.log("tmdb fetch hit source=persisted hash=\(scopedHash) path=\(path)")
                return URL(string: imageBaseURL + path)
            } else if persistedMatch.isManualOverride {
                TransfersPosterDiagnostics.log("tmdb fetch hit source=persisted-manual-nil hash=\(scopedHash)")
                return nil
            }
        }

        // 2.1 Legacy manual override migration (old hash key without language scope)
        if let legacyManualMatch = persistedPosterMatchesByHash[hash],
           legacyManualMatch.isManualOverride,
           let path = legacyManualMatch.posterPath {
            let scopedMatch = TMDBMatch(hashString: scopedHash, posterPath: path, isManualOverride: true)
            context.insert(scopedMatch)
            rememberPersistedPosterMatch(scopedMatch)
            cacheURL(path, for: scopedHash)
            cacheURL(path, for: scopedCacheKey)
            try? context.save()
            TransfersPosterDiagnostics.log("tmdb fetch hit source=legacy-persisted hash=\(scopedHash) path=\(path)")
            return URL(string: imageBaseURL + path)
        }

        // 3. Migration: Check Legacy UserDefaults
        if let legacyPath = legacyOverrides[hash] {
            let match = TMDBMatch(hashString: scopedHash, posterPath: legacyPath, isManualOverride: true)
            context.insert(match)
            rememberPersistedPosterMatch(match)
            cacheURL(legacyPath, for: scopedHash)
            cacheURL(legacyPath, for: scopedCacheKey)
            TransfersPosterDiagnostics.log("tmdb fetch hit source=legacy-userdefaults hash=\(scopedHash) path=\(legacyPath)")
            return URL(string: imageBaseURL + legacyPath)
        }

        // 4. Clean Name & Search (Network)
        let metadata = OiiQTParser.parse(name)
        log("[TMDB] fetchPoster: parsed '\(name)' → title: '\(metadata.title)', year: \(metadata.year ?? "nil"), english: \(metadata.englishTitle ?? "nil")")
        guard !metadata.title.isEmpty else {
            log("[TMDB] fetchPoster: SKIP empty title for '\(name)'")
            TransfersPosterDiagnostics.log("tmdb fetch skip empty-title hash=\(scopedHash) name=\(name)")
            return nil
        }

        // Search with smart matching (title + year + fallback)
        guard let posterPath = await searchBestMatch(metadata: metadata, apiKeySource: .default) else {
             let match = TMDBMatch(hashString: scopedHash, posterPath: nil, isManualOverride: false)
             context.insert(match)
             rememberPersistedPosterMatch(match)
             urlCache.setObject("null", forKey: scopedHash as NSString)
             urlCache.setObject("null", forKey: scopedCacheKey as NSString)
            log("[TMDB] fetchPoster: NO MATCH for '\(name)'")
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
            let elapsedText = String(format: "%.1f", elapsedMs)
            TransfersPosterDiagnostics.log(
                "tmdb fetch miss source=network hash=\(scopedHash) elapsedMs=\(elapsedText)"
            )
            return nil
        }

        // 5. Save Match
        let match = TMDBMatch(hashString: scopedHash, posterPath: posterPath, isManualOverride: false)
        context.insert(match)
        rememberPersistedPosterMatch(match)
        cacheURL(posterPath, for: scopedHash)
        cacheURL(posterPath, for: scopedCacheKey)

        log("[TMDB] fetchPoster: MATCHED '\(name)' → \(posterPath)")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
        let elapsedText = String(format: "%.1f", elapsedMs)
        TransfersPosterDiagnostics.log(
            "tmdb fetch hit source=network hash=\(scopedHash) path=\(posterPath) elapsedMs=\(elapsedText)"
        )
        return URL(string: imageBaseURL + posterPath)
    }

    /// 获取背景大图 (Backdrop 16:9)
    @MainActor
    func fetchBackdrop(hash: String, name: String, context: ModelContext) async -> URL? {
        let scopedHash = scopedHash(for: hash)

        // 1. Check persistence (SwiftData)
        // We generally use persisted path if available
        if let match = fetchMatch(hash: scopedHash, context: context) {
            if let path = match.backdropPath {
                return URL(string: "https://image.tmdb.org/t/p/w780" + path)
            }
            // If match exists but no backdrop, maybe we haven't fetched it yet?
            // Or maybe it has none?
            // If match.isManualOverride, we trust it?
            // For now, if no backdropPath, we try to search again and update.
        }

        // 2. Network Search
        let metadata = OiiQTParser.parse(name)
        guard !metadata.title.isEmpty else { return nil }

        let items = await search(query: metadata.title)
        let bestItem = selectBestMatch(from: items, year: metadata.year)
        guard let backdropPath = bestItem?.backdropPath else { return nil }

        // 3. Save/Update Match
        if let match = fetchMatch(hash: scopedHash, context: context) {
            match.backdropPath = backdropPath
        } else {
             // If no match existed, create one?
             // Usually fetchPoster is called first, so match likely exists.
             // But if not, we create one.
             let match = TMDBMatch(hashString: scopedHash, posterPath: items.first?.posterPath, backdropPath: backdropPath, isManualOverride: false)
             context.insert(match)
             rememberPersistedPosterMatch(match)
        }

        return URL(string: "https://image.tmdb.org/t/p/w780" + backdropPath)
    }

    @MainActor
    func prefetchPosters(
        for tasks: [TorrentTask],
        limit: Int = 24,
        context: ModelContext
    ) async {
        guard !tasks.isEmpty, limit > 0 else { return }

        hydratePersistedPosterMatchesIfNeeded(context: context)

        var seenTaskIDs = Set<String>()
        let candidates = tasks.lazy
            .filter { seenTaskIDs.insert($0.id).inserted }
            .prefix(limit)

        for task in candidates {
            guard !Task.isCancelled else { return }
            _ = await fetchPoster(hash: task.hash, name: task.name, context: context)
            await Task.yield()
        }
    }

    /// 获取完整详情 (用于 Detail View)
    @MainActor
    func fetchDetails(hash: String, name: String, context: ModelContext) async -> TMDBItem? {
        let scopedHash = scopedHash(for: hash)
        TransfersPosterDiagnostics.log("tmdb details start hash=\(scopedHash) name=\(name)")

        let storedMatch = fetchMatch(hash: scopedHash, context: context) ?? fetchLegacyManualMatch(hash: hash, context: context)
        if let storedMatch, storedMatch.isManualOverride, let cachedManualItem = manualCachedTMDBItem(from: storedMatch) {
            TransfersPosterDiagnostics.log("tmdb details hit source=manual hash=\(scopedHash) title=\(cachedManualItem.title)")
            return cachedManualItem
        }

        // 1. Try to find existing manual match or cached match to guide us?
        // Since we don't store ID, we have to search again.
        // Optimization: If we have a stored posterPath, we can try to find the item that matches that posterPath in the search results.

        // 2. Parse & Search
        let metadata = OiiQTParser.parse(name)
        guard !metadata.title.isEmpty else {
            TransfersPosterDiagnostics.log("tmdb details skip reason=empty-title hash=\(scopedHash)")
            return nil
        }

        let items = await search(query: metadata.title)
        TransfersPosterDiagnostics.log(
            "tmdb details primary title=\(metadata.title) year=\(metadata.year ?? "nil") results=\(items.count)"
        )

        // 3. Select Best Match
        // If we have a stored poster path (from fetchPoster), we should prefer the item that has that path.
        if let storedPoster = storedMatch?.posterPath {
            if let exact = items.first(where: { $0.posterPath == storedPoster }) {
                TransfersPosterDiagnostics.log("tmdb details hit source=poster-path hash=\(scopedHash) title=\(exact.title)")
                return exact
            }
        }

        // Otherwise use smart match logic
        if let best = selectBestMatch(from: items, year: metadata.year) {
            TransfersPosterDiagnostics.log("tmdb details hit source=primary-search hash=\(scopedHash) title=\(best.title)")
            return best
        }

        // Fallback: English Title
        if let englishTitle = metadata.englishTitle, !englishTitle.isEmpty {
             let enItems = await search(query: englishTitle)
             TransfersPosterDiagnostics.log(
                "tmdb details fallback title=\(englishTitle) year=\(metadata.year ?? "nil") results=\(enItems.count)"
             )
             if let best = selectBestMatch(from: enItems, year: metadata.year) {
                 TransfersPosterDiagnostics.log("tmdb details hit source=fallback-search hash=\(scopedHash) title=\(best.title)")
                 return best
             }
        }

        TransfersPosterDiagnostics.log("tmdb details fail hash=\(scopedHash) name=\(name)")
        return nil
    }

    /// 搜索 API (支持分页，自动重试一次)
    func search(
        query: String,
        page: Int = 1,
        apiKeySource: TMDBAPIKeySource = .default
    ) async -> [TMDBItem] {
        let normalizedQuery = extractCleanCacheKey(from: query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let language = currentTMDBLanguage()
        guard let apiKey = apiKey(for: apiKeySource),
              apiKey != "YOUR_API_KEY_HERE",
              let encodedQuery = normalizedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/multi?api_key=\(apiKey)&query=\(encodedQuery)&language=\(language)&page=\(page)") else {
            log("[TMDB] search: SKIP (invalid API key or query encoding) for '\(query)'")
            return []
        }

        let cacheKey = searchCacheKey(
            query: normalizedQuery,
            page: page,
            language: language,
            apiKeySource: apiKeySource
        )
        let lookup = await searchCoordinator.cachedOrTask(for: cacheKey) { [self] in
            Task { [self] in
                await self.performSearchRequest(
                    url: url,
                    query: normalizedQuery,
                    language: language,
                    cacheKey: cacheKey,
                    apiKeySource: apiKeySource
                )
            }
        }

        switch lookup {
        case .cached(let items):
            log("[TMDB] search: metadata cache HIT for '\(normalizedQuery)' (language: \(language), page: \(page), source: \(apiKeySource.rawValue))")
            TransfersPosterDiagnostics.log(
                "tmdb search cache hit query=\(normalizedQuery) language=\(language) page=\(page) source=\(apiKeySource.rawValue) results=\(items.count)"
            )
            return items
        case .task(let task):
            return await task.value
        }
    }

    /// 保存手动匹配结果
    @MainActor
    func saveOverride(hash: String, posterPath: String, context: ModelContext) {
        let scopedHash = scopedHash(for: hash)

        // 1. Check existing
        if let existing = fetchMatch(hash: scopedHash, context: context) {
            existing.posterPath = posterPath
            existing.isManualOverride = true
            existing.lastMatchedTime = Date()
            rememberPersistedPosterMatch(existing)
        } else {
            let match = TMDBMatch(hashString: scopedHash, posterPath: posterPath, isManualOverride: true)
            context.insert(match)
            rememberPersistedPosterMatch(match)
        }

        // 2. Update Memory
        cacheURL(posterPath, for: scopedHash)

        // 3. Persist
        try? context.save()
    }

    /// 保存手动匹配结果（完整条目，用于详情页直接展示）
    @MainActor
    func saveOverride(hash: String, item: TMDBItem, context: ModelContext) {
        guard let posterPath = item.posterPath else { return }
        let scopedHash = scopedHash(for: hash)

        if let existing = fetchMatch(hash: scopedHash, context: context) {
            existing.posterPath = posterPath
            existing.backdropPath = item.backdropPath
            existing.tmdbID = item.id
            existing.tmdbTitle = item.title
            existing.tmdbReleaseDate = item.releaseDate
            existing.tmdbMediaType = item.mediaType
            existing.tmdbOverview = item.overview
            existing.tmdbVoteAverage = item.voteAverage
            existing.isManualOverride = true
            existing.lastMatchedTime = Date()
            rememberPersistedPosterMatch(existing)
        } else {
            let match = TMDBMatch(
                hashString: scopedHash,
                posterPath: posterPath,
                backdropPath: item.backdropPath,
                tmdbID: item.id,
                tmdbTitle: item.title,
                tmdbReleaseDate: item.releaseDate,
                tmdbMediaType: item.mediaType,
                tmdbOverview: item.overview,
                tmdbVoteAverage: item.voteAverage,
                isManualOverride: true
            )
            context.insert(match)
            rememberPersistedPosterMatch(match)
        }

        cacheURL(posterPath, for: scopedHash)
        try? context.save()
    }

    /// 清除特定 hash 的内存缓存，允许重新匹配
    func clearCache(for hash: String, name: String? = nil) {
        urlCache.removeObject(forKey: hash as NSString)
        for languageCode in ["zh-Hans", "en"] {
            let scoped = scopedHash(for: hash, languageCode: languageCode)
            urlCache.removeObject(forKey: scoped as NSString)
        }
        if let name {
            let cacheKey = extractCleanCacheKey(from: name)
            for languageCode in ["zh-Hans", "en"] {
                let scoped = scopedPosterCacheKey(for: cacheKey, languageCode: languageCode)
                urlCache.removeObject(forKey: scoped as NSString)
            }
        }
    }

    /// 清除特定任务的海报缓存（内存 + 持久化匹配），用于“重新匹配海报”
    @MainActor
    func clearPosterMatch(for hash: String, name: String? = nil, context: ModelContext) {
        clearCache(for: hash, name: name)

        var keys = Set<String>()
        keys.insert(hash)
        keys.insert(scopedHash(for: hash))
        keys.insert(scopedHash(for: hash, languageCode: "zh-Hans"))
        keys.insert(scopedHash(for: hash, languageCode: "en"))

        for key in keys {
            persistedPosterMatchesByHash.removeValue(forKey: key)
            let descriptor = FetchDescriptor<TMDBMatch>(
                predicate: #Predicate { $0.hashString == key }
            )
            if let matches = try? context.fetch(descriptor) {
                for match in matches {
                    context.delete(match)
                }
            }
        }

        try? context.save()
    }

    // MARK: - Private Helpers

    @MainActor
    private func fetchMatch(hash: String, context: ModelContext) -> TMDBMatch? {
        let descriptor = FetchDescriptor<TMDBMatch>(
            predicate: #Predicate { $0.hashString == hash }
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private func hydratePersistedPosterMatchesIfNeeded(context: ModelContext) {
        guard !hasHydratedPersistedPosterMatches else { return }

        let descriptor = FetchDescriptor<TMDBMatch>()
        let matches = (try? context.fetch(descriptor)) ?? []
        persistedPosterMatchesByHash = Dictionary(
            uniqueKeysWithValues: matches.map { ($0.hashString, PersistedPosterMatch(match: $0)) }
        )
        hasHydratedPersistedPosterMatches = true
    }

    @MainActor
    private func rememberPersistedPosterMatch(_ match: TMDBMatch) {
        persistedPosterMatchesByHash[match.hashString] = PersistedPosterMatch(match: match)
    }

    private func cacheURL(_ path: String, for hash: String) {
        urlCache.setObject(path as NSString, forKey: hash as NSString)
    }

    private static let cleanCacheKeyRegex: NSRegularExpression? = {
        let pattern = "(?i)[\\.\\s_\\-\\[\\(]*(S\\d{2}(E\\d{2})?|(19|20)\\d{2}|2160p|1080p|720p|4k|WEB-DL|BluRay|x265|H265).*$"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private func extractCleanCacheKey(from rawName: String) -> String {
        guard let regex = Self.cleanCacheKeyRegex else { return rawName }
        let range = NSRange(rawName.startIndex..., in: rawName)
        let cleaned = regex.stringByReplacingMatches(in: rawName, options: [], range: range, withTemplate: "")
        let finalTitle = cleaned
            .trimmingCharacters(in: CharacterSet(charactersIn: ". _-[]()"))
            .trimmingCharacters(in: .whitespaces)
        return finalTitle.isEmpty ? rawName : finalTitle
    }

    /// Smart search with fallback strategy:
    /// 1. Chinese title + year → best year-matched result
    /// 2. Chinese title only → best result
    /// 3. English title + year (if available) → best year-matched result
    /// 4. English title only → first result
    private func searchBestMatch(
        metadata: OiiQTMetadata,
        apiKeySource: TMDBAPIKeySource
    ) async -> String? {
        // Strategy 1: Primary title (Chinese if available)
        let primaryResults = await search(query: metadata.title, apiKeySource: apiKeySource)
        TransfersPosterDiagnostics.log(
            "tmdb search primary title=\(metadata.title) year=\(metadata.year ?? "nil") source=\(apiKeySource.rawValue) results=\(primaryResults.count)"
        )
        if let best = selectBestMatch(from: primaryResults, year: metadata.year) {
            log("[TMDB] Matched '\(metadata.title)' (year: \(metadata.year ?? "nil")) → \(best.title)")
            return best.posterPath
        }

        // Strategy 2: English title fallback (if different from primary)
        if let englishTitle = metadata.englishTitle, !englishTitle.isEmpty {
            let englishResults = await search(query: englishTitle, apiKeySource: apiKeySource)
            TransfersPosterDiagnostics.log(
                "tmdb search fallback title=\(englishTitle) year=\(metadata.year ?? "nil") source=\(apiKeySource.rawValue) results=\(englishResults.count)"
            )
            if let best = selectBestMatch(from: englishResults, year: metadata.year) {
                log("[TMDB] Matched English '\(englishTitle)' (year: \(metadata.year ?? "nil")) → \(best.title)")
                return best.posterPath
            }
        }

        log("[TMDB] No match for '\(metadata.title)'")
        return nil
    }

    /// Select the best match from TMDB results using year scoring
    /// Only considers items with a posterPath; falls back to first item with poster if no year match
    private func selectBestMatch(from items: [TMDBItem], year: String?) -> TMDBItem? {
        let withPoster = items.filter { $0.posterPath != nil }
        guard !withPoster.isEmpty else { return nil }

        guard let targetYear = year else {
            return withPoster.first
        }

        var bestItem: TMDBItem?
        var bestScore = -1

        for (index, item) in withPoster.enumerated() {
            var score = 0

            if item.year == targetYear {
                score += 100
            } else if let itemYear = Int(item.year), let target = Int(targetYear), abs(itemYear - target) <= 1 {
                score += 50
            }

            // Prefer earlier results (TMDB relevance order)
            score += max(0, 10 - index)

            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }

        return bestItem
    }

    private func currentTMDBLanguage() -> String {
        currentStorageLanguageCode().hasPrefix("zh") ? "zh-CN" : "en-US"
    }

    private func currentStorageLanguageCode() -> String {
        let storedCode = UserDefaults.standard.string(forKey: "language")?.lowercased()
        let preferredCode = Locale.preferredLanguages.first?.lowercased()
        let resolvedCode = storedCode ?? preferredCode ?? "en"
        return resolvedCode.hasPrefix("zh") ? "zh-Hans" : "en"
    }

    private func scopedHash(for hash: String, languageCode: String? = nil) -> String {
        let code = (languageCode ?? currentStorageLanguageCode()).lowercased()
        return "\(hash)::\(code)"
    }

    private func scopedPosterCacheKey(for cacheKey: String, languageCode: String? = nil) -> String {
        let code = (languageCode ?? currentStorageLanguageCode()).lowercased()
        return "poster::\(cacheKey.lowercased())::\(code)"
    }

    private func searchCacheKey(
        query: String,
        page: Int,
        language: String,
        apiKeySource: TMDBAPIKeySource
    ) -> String {
        "\(apiKeySource.rawValue.lowercased())|\(language.lowercased())|\(page)|\(query.lowercased())"
    }

    @MainActor
    private func fetchLegacyManualMatch(hash: String, context: ModelContext) -> TMDBMatch? {
        guard let legacy = fetchMatch(hash: hash, context: context) else { return nil }
        return legacy.isManualOverride ? legacy : nil
    }

    private func manualCachedTMDBItem(from match: TMDBMatch) -> TMDBItem? {
        guard let id = match.tmdbID,
              let title = match.tmdbTitle,
              let mediaType = match.tmdbMediaType else {
            return nil
        }
        return TMDBItem(
            id: id,
            title: title,
            posterPath: match.posterPath,
            backdropPath: match.backdropPath,
            releaseDate: match.tmdbReleaseDate,
            mediaType: mediaType,
            overview: match.tmdbOverview,
            voteAverage: match.tmdbVoteAverage
        )
    }

    private func apiKey(for source: TMDBAPIKeySource) -> String? {
        switch source {
        case .default:
            return apiKeyToUse
        case .custom:
            return customAPIKey
        case .builtIn:
            return builtInAPIKey
        }
    }

    private func performSearchRequest(
        url: URL,
        query: String,
        language: String,
        cacheKey: String,
        apiKeySource: TMDBAPIKeySource
    ) async -> [TMDBItem] {
        await searchCoordinator.acquirePermit()

        var resultItems: [TMDBItem] = []
        var shouldCacheResult = false

        for attempt in 1...2 {
            let startUptime = DispatchTime.now().uptimeNanoseconds
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
                let items = response.results.compactMap { $0.toDomainModel() }
                log("[TMDB] search: query='\(query)', language='\(language)' → \(items.count) results, first 3: \(items.prefix(3).map { "[\($0.title), year=\($0.year), poster=\($0.posterPath != nil)]" })")
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
                let elapsedText = String(format: "%.1f", elapsedMs)
                TransfersPosterDiagnostics.log(
                    "tmdb search request finish query=\(query) language=\(language) source=\(apiKeySource.rawValue) attempt=\(attempt) results=\(items.count) elapsedMs=\(elapsedText)"
                )
                resultItems = items
                shouldCacheResult = true
                break
            } catch {
                log("[TMDB] Search Error (attempt \(attempt)) for '\(query)': \(error)")
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000
                let elapsedText = String(format: "%.1f", elapsedMs)
                TransfersPosterDiagnostics.log(
                    "tmdb search request error query=\(query) language=\(language) source=\(apiKeySource.rawValue) attempt=\(attempt) elapsedMs=\(elapsedText) error=\(error.localizedDescription)"
                )
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        await searchCoordinator.completeRequest(for: cacheKey, result: resultItems, cacheable: shouldCacheResult)
        return resultItems
    }

    private func log(_ message: @autoclosure () -> String) {
#if DEBUG
        guard isVerboseLoggingEnabled else { return }
        print(message())
#endif
    }
}

extension Notification.Name {
    static let tmdbPosterDidChange = Notification.Name("tmdbPosterDidChange")
}

private struct PersistedPosterMatch {
    let hashString: String
    let posterPath: String?
    let isManualOverride: Bool

    init(match: TMDBMatch) {
        self.hashString = match.hashString
        self.posterPath = match.posterPath
        self.isManualOverride = match.isManualOverride
    }
}

private actor TMDBSearchCoordinator {
    enum Lookup {
        case cached([TMDBItem])
        case task(Task<[TMDBItem], Never>)
    }

    private let maxConcurrentRequests: Int
    private let maxCachedEntries: Int
    private var activeRequests: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var metadataCache: [String: [TMDBItem]] = [:]
    private var metadataCacheOrder: [String] = []
    private var inFlightTasks: [String: Task<[TMDBItem], Never>] = [:]

    init(maxConcurrentRequests: Int, maxCachedEntries: Int) {
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
        self.maxCachedEntries = max(16, maxCachedEntries)
    }

    func cachedOrTask(
        for cacheKey: String,
        makeTask: @escaping @Sendable () -> Task<[TMDBItem], Never>
    ) -> Lookup {
        if let cached = metadataCache[cacheKey] {
            touchCacheKey(cacheKey)
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

    func completeRequest(for cacheKey: String, result: [TMDBItem], cacheable: Bool) {
        if cacheable {
            metadataCache[cacheKey] = result
            touchCacheKey(cacheKey)
            evictIfNeeded()
        }
        inFlightTasks[cacheKey] = nil
        releasePermit()
    }

    private func touchCacheKey(_ cacheKey: String) {
        metadataCacheOrder.removeAll(where: { $0 == cacheKey })
        metadataCacheOrder.append(cacheKey)
    }

    private func evictIfNeeded() {
        while metadataCacheOrder.count > maxCachedEntries {
            let oldestKey = metadataCacheOrder.removeFirst()
            metadataCache.removeValue(forKey: oldestKey)
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

// MARK: - Models

struct TMDBItem: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let mediaType: String // "movie" or "tv"
    let overview: String?
    let voteAverage: Double?

    var fullPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300" + path)
    }

    var fullBackdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780" + path)
    }

    var year: String {
        releaseDate?.components(separatedBy: "-").first ?? ""
    }

    // UI Helpers
    var typeLabel: String {
        mediaType == "movie"
            ? LanguageManager.shared.localized("Movie")
            : LanguageManager.shared.localized("TV Series")
    }
}

// MARK: - Decodable Helpers

private struct TMDBResponse: Decodable {
    let results: [TMDBResult]
}

private struct TMDBResult: Decodable {
    let id: Int
    let poster_path: String?
    let backdrop_path: String?
    let media_type: String?
    let title: String?
    let name: String?
    let release_date: String?
    let first_air_date: String?
    let overview: String?
    let vote_average: Double?

    func toDomainModel() -> TMDBItem? {
        // Only movies and tv shows
        guard ["movie", "tv"].contains(media_type) else { return nil }

        // Return item
        return TMDBItem(
            id: id,
            title: title ?? name ?? "Unknown",
            posterPath: poster_path,
            backdropPath: backdrop_path,
            releaseDate: release_date ?? first_air_date,
            mediaType: media_type ?? "unknown",
            overview: overview,
            voteAverage: vote_average
        )
    }
}
