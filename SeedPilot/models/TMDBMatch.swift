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
    var lastMatchedTime: Date // 上次匹配时间 (用于缓存失效策略?)
    var isManualOverride: Bool // 是否为手动匹配 (Manual beats Auto)

    init(hashString: String, posterPath: String?, backdropPath: String? = nil, isManualOverride: Bool = false) {
        self.hashString = hashString
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.lastMatchedTime = Date()
        self.isManualOverride = isManualOverride
    }
}
