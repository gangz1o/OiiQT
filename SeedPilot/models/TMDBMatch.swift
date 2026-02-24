//
//  TMDBMatch.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation
import SwiftData

@Model
final class TMDBMatch {
    @Attribute(.unique) var hashString: String // 种子哈希
    var posterPath: String? // TMDB Poster URL Path
    var backdropPath: String? // TMDB Backdrop URL Path (16:9)
    var tmdbID: Int? // 手动匹配时缓存 TMDB 条目 ID
    var tmdbTitle: String? // 手动匹配时缓存标题
    var tmdbReleaseDate: String? // 手动匹配时缓存上映/首播日期
    var tmdbMediaType: String? // 手动匹配时缓存 mediaType (movie/tv)
    var tmdbOverview: String? // 手动匹配时缓存简介
    var tmdbVoteAverage: Double? // 手动匹配时缓存评分
    var lastMatchedTime: Date // 上次匹配时间 (用于缓存失效策略?)
    var isManualOverride: Bool // 是否为手动匹配 (Manual beats Auto)

    init(
        hashString: String,
        posterPath: String?,
        backdropPath: String? = nil,
        tmdbID: Int? = nil,
        tmdbTitle: String? = nil,
        tmdbReleaseDate: String? = nil,
        tmdbMediaType: String? = nil,
        tmdbOverview: String? = nil,
        tmdbVoteAverage: Double? = nil,
        isManualOverride: Bool = false
    ) {
        self.hashString = hashString
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.tmdbID = tmdbID
        self.tmdbTitle = tmdbTitle
        self.tmdbReleaseDate = tmdbReleaseDate
        self.tmdbMediaType = tmdbMediaType
        self.tmdbOverview = tmdbOverview
        self.tmdbVoteAverage = tmdbVoteAverage
        self.lastMatchedTime = Date()
        self.isManualOverride = isManualOverride
    }
}
