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
            } else {
                // Matched but no poster?
                return nil
            }
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
        let cleanedName = cleanTorrentName(name)
        guard !cleanedName.isEmpty else { return nil }

        // Search
        guard let posterPath = await searchFirstMatch(query: cleanedName) else {
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

    private func searchFirstMatch(query: String) async -> String? {
        let items = await search(query: query)
        return items.first?.posterPath
    }

    /// 清洗种子名称，提取核心标题
    private func cleanTorrentName(_ name: String) -> String {
        return SeedPilotParser.parse(name).title
    }
}

// MARK: - Models

struct TMDBItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let posterPath: String?
    let releaseDate: String?
    let mediaType: String // "movie" or "tv"

    var fullPosterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300" + path)
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
    let media_type: String?
    let title: String?
    let name: String?
    let release_date: String?
    let first_air_date: String?

    func toDomainModel() -> TMDBItem? {
        guard ["movie", "tv"].contains(media_type) else { return nil }
        return TMDBItem(
            id: id,
            title: title ?? name ?? "Unknown",
            posterPath: poster_path,
            releaseDate: release_date ?? first_air_date,
            mediaType: media_type ?? "unknown"
        )
    }
}
