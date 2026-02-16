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
    func matches(item: RSSItem, source: RSSFeedSource) -> Bool {
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
        var clean = title

        // Remove content in brackets [...]
        clean = clean.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)

        // Remove content in parentheses (...)
        clean = clean.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)

        // Remove common patterns like S01E01, 1080p, etc.
        let patterns = [
            "S\\d{2}E\\d{2}", // S01E01
            "1080p|720p|2160p|4K|REMUX|HEVC|x264|x265|AAC|FLAC", // Tech specs
            "\\d{4}" // Year (maybe keep year? TMDB uses it, but often strict matching fails. Let's keep year if it looks like (Year) but we stripped parens above)
        ]

        for pattern in patterns {
             clean = clean.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // Replace dots/underscores with spaces
        clean = clean.replacingOccurrences(of: "\\.|_", with: " ", options: .regularExpression)

        // Trim whitespace
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
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
