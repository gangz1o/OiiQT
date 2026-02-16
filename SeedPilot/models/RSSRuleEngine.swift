//
//  RSSRuleEngine.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

class RSSRuleEngine {
    static let shared = RSSRuleEngine()

    // Matches an item against a source's rules
    func matchesRule(item: RSSItem, source: RSSFeedSource) -> Bool {
        // 1. Must match ALL include keywords (if any)
        if !source.includeKeywords.isEmpty {
            let title = item.title.lowercased()
            for keyword in source.includeKeywords {
                if !title.contains(keyword.lowercased()) {
                    return false
                }
            }
        }

        // 2. Must NOT match ANY exclude keywords (if any)
        if !source.excludeKeywords.isEmpty {
            let title = item.title.lowercased()
            for keyword in source.excludeKeywords {
                if title.contains(keyword.lowercased()) {
                    return false
                }
            }
        }

        // 3. Size check (if available)
        if let sizeStr = item.fileSize, let sizeGB = parseSizeToGB(sizeStr) {
            if let min = source.minSizeGB, sizeGB < min { return false }
            if let max = source.maxSizeGB, sizeGB > max { return false }
        }

        return true
    }

    // Cleans title for TMDB search (removes tags, quality, etc)
    func cleanTitleForTMDB(_ title: String) -> String {
        return TitleParser.parse(title).cleanTitle
    }

    // Helper: Parse "1.2 GB", "500 MB" to Double (GB)
    private func parseSizeToGB(_ sizeStr: String) -> Double? {
        let components = sizeStr.split(separator: " ")
        guard let valueStr = components.first, let value = Double(valueStr) else { return nil }

        if sizeStr.contains("GB") || sizeStr.contains("GiB") {
            return value
        } else if sizeStr.contains("MB") || sizeStr.contains("MiB") {
            return value / 1024.0
        } else if sizeStr.contains("TB") || sizeStr.contains("TiB") {
            return value * 1024.0
        }
        return nil // assume fail or KB
    }
}
