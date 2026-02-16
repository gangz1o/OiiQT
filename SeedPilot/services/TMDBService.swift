//
//  TMDBService.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import Foundation
import SwiftUI

import SwiftData

class TMDBService {
    static let shared = TMDBService()

    // MARK: - Configuration
    // 此功能仅供 Pro 付费用户开启
    private let apiKey = "24c4e7a516af276925d44ac5cc90a59f"
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p/w300"
    private let overridesKey = "tmdb_overrides"

    // MARK: - Caching
    // Memory Cache for Hash -> PosterURLString (NOT Image data, just mapping)
    // Image data is handled by ImageCacheManager
    private let urlCache = NSCache<NSString, NSString>()

    // Legacy UserDefaults (for migration)
    private var legacyOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overridesKey) }
    }

    private init() {}

    // MARK: - Public API

    /// 根据种子获取海报 URL
    /// - Parameters:
    ///   - hash: 种子 Hash (ID)
    ///   - name: 种子名称 (用于搜索)
    ///   - context: SwiftData Context (from View)
    @MainActor
    func fetchPoster(hash: String, name: String, context: ModelContext) async -> URL? {
        // 1. Check Memory URL Cache first
        if let cachedPath = urlCache.object(forKey: hash as NSString) as String? {
             // Specific "null" check just in case we cached a failure to avoid loop
            if cachedPath == "null" { return nil }
            return URL(string: imageBaseURL + cachedPath)
        }

        // 2. data persistence (SwiftData)
        if let match = fetchMatch(hash: hash, context: context) {
            if let path = match.posterPath {
                cacheURL(path, for: hash)
                return URL(string: imageBaseURL + path)
            } else if match.isManualOverride {
                // Manual override with no poster — respect user choice
                return nil
            } else if match.lastMatchedTime.timeIntervalSinceNow > -86400 * 3 {
                // Auto-matched failure less than 3 days old — don't retry yet
                return nil
            }
            // Auto-matched failure older than 3 days — allow retry with improved algorithm
            context.delete(match)
        }

        // 3. Migration: Check Legacy UserDefaults
        if let legacyPath = legacyOverrides[hash] {
            // Migrate to SwiftData
            let match = TMDBMatch(hashString: hash, posterPath: legacyPath, isManualOverride: true)
            context.insert(match)

            cacheURL(legacyPath, for: hash)
            return URL(string: imageBaseURL + legacyPath)
        }

        // 4. Clean Name & Search (Network)
        let metadata = SeedPilotParser.parse(name)
        guard !metadata.title.isEmpty else { return nil }

        // Search with smart matching (title + year + fallback)
        guard let posterPath = await searchBestMatch(metadata: metadata) else {
             let match = TMDBMatch(hashString: hash, posterPath: nil, isManualOverride: false)
             context.insert(match)
             urlCache.setObject("null", forKey: hash as NSString)
            return nil
        }

        // 5. Save Match
        let match = TMDBMatch(hashString: hash, posterPath: posterPath, isManualOverride: false)
        context.insert(match)
        cacheURL(posterPath, for: hash)

        return URL(string: imageBaseURL + posterPath)
    }

    /// 获取背景大图 (Backdrop 16:9)
    @MainActor
    func fetchBackdrop(hash: String, name: String, context: ModelContext) async -> URL? {
        // 1. Check persistence (SwiftData)
        // We generally use persisted path if available
        if let match = fetchMatch(hash: hash, context: context) {
            if let path = match.backdropPath {
                return URL(string: "https://image.tmdb.org/t/p/w780" + path)
            }
            // If match exists but no backdrop, maybe we haven't fetched it yet?
            // Or maybe it has none?
            // If match.isManualOverride, we trust it?
            // For now, if no backdropPath, we try to search again and update.
        }

        // 2. Network Search
        let metadata = SeedPilotParser.parse(name)
        guard !metadata.title.isEmpty else { return nil }

        let items = await search(query: metadata.title)
        let bestItem = selectBestMatch(from: items, year: metadata.year)
        guard let backdropPath = bestItem?.backdropPath else { return nil }

        // 3. Save/Update Match
        if let match = fetchMatch(hash: hash, context: context) {
            match.backdropPath = backdropPath
        } else {
             // If no match existed, create one?
             // Usually fetchPoster is called first, so match likely exists.
             // But if not, we create one.
             let match = TMDBMatch(hashString: hash, posterPath: items.first?.posterPath, backdropPath: backdropPath, isManualOverride: false)
             context.insert(match)
        }

        return URL(string: "https://image.tmdb.org/t/p/w780" + backdropPath)
    }

    /// 搜索 API (支持分页)
    func search(query: String, page: Int = 1) async -> [TMDBItem] {
        guard apiKey != "YOUR_API_KEY_HERE",
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/multi?api_key=\(apiKey)&query=\(encodedQuery)&language=zh-CN&page=\(page)") else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
            return response.results.compactMap { $0.toDomainModel() }
        } catch {
            print("TMDB Search Error: \(error)")
            return []
        }
    }

    /// 保存手动匹配结果
    @MainActor
    func saveOverride(hash: String, posterPath: String, context: ModelContext) {
        // 1. Check existing
        if let existing = fetchMatch(hash: hash, context: context) {
            existing.posterPath = posterPath
            existing.isManualOverride = true
            existing.lastMatchedTime = Date()
        } else {
            let match = TMDBMatch(hashString: hash, posterPath: posterPath, isManualOverride: true)
            context.insert(match)
        }

        // 2. Update Memory
        cacheURL(posterPath, for: hash)

        // 3. Persist
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

    private func cacheURL(_ path: String, for hash: String) {
        urlCache.setObject(path as NSString, forKey: hash as NSString)
    }

    /// Smart search with fallback strategy:
    /// 1. Chinese title + year → best year-matched result
    /// 2. Chinese title only → best result
    /// 3. English title + year (if available) → best year-matched result
    /// 4. English title only → first result
    private func searchBestMatch(metadata: SeedPilotMetadata) async -> String? {
        // Strategy 1: Primary title (Chinese if available)
        let primaryResults = await search(query: metadata.title)
        if let best = selectBestMatch(from: primaryResults, year: metadata.year) {
            print("[TMDB] Matched '\(metadata.title)' (year: \(metadata.year ?? "nil")) → \(best.title)")
            return best.posterPath
        }

        // Strategy 2: English title fallback (if different from primary)
        if let englishTitle = metadata.englishTitle, !englishTitle.isEmpty {
            let englishResults = await search(query: englishTitle)
            if let best = selectBestMatch(from: englishResults, year: metadata.year) {
                print("[TMDB] Matched English '\(englishTitle)' (year: \(metadata.year ?? "nil")) → \(best.title)")
                return best.posterPath
            }
        }

        print("[TMDB] No match for '\(metadata.title)'")
        return nil
    }

    /// Select the best match from TMDB results using year scoring
    private func selectBestMatch(from items: [TMDBItem], year: String?) -> TMDBItem? {
        guard !items.isEmpty else { return nil }
        guard let targetYear = year else {
            // No year info, return first result with a poster
            return items.first { $0.posterPath != nil } ?? items.first
        }
        
        // Score each result: year match is highest priority
        var bestItem: TMDBItem?
        var bestScore = -1
        
        for item in items {
            var score = 0
            
            // Year matching (highest weight)
            if item.year == targetYear {
                score += 100
            } else if let itemYear = Int(item.year), let target = Int(targetYear), abs(itemYear - target) <= 1 {
                // Allow 1 year tolerance (release date variance between regions)
                score += 50
            }
            
            // Has poster (required for useful result)
            if item.posterPath != nil {
                score += 10
            }
            
            // Prefer results that appear earlier in search results (TMDB relevance)
            // First results get a small bonus
            if bestItem == nil {
                score += 5
            }
            
            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }
        
        return bestItem
    }
}

// MARK: - Models

struct TMDBItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let mediaType: String // "movie" or "tv"

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
        mediaType == "movie" ? "电影" : "剧集"
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
            mediaType: media_type ?? "unknown"
        )
    }
}


