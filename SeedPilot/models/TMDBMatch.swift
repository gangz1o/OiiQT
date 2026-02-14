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
    var lastMatchedTime: Date // 上次匹配时间 (用于缓存失效策略?)
    var isManualOverride: Bool // 是否为手动匹配 (Manual beats Auto)

    init(hashString: String, posterPath: String?, isManualOverride: Bool = false) {
        self.hashString = hashString
        self.posterPath = posterPath
        self.lastMatchedTime = Date()
        self.isManualOverride = isManualOverride
    }
}
