//
//  RSSRuleEngine.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

class RSSRuleEngine {
    static let shared = RSSRuleEngine()

    private struct EpisodeMarker {
        let season: Int?
        let episode: Int
    }

    private enum EpisodeRule {
        case single(EpisodeMarker)
        case range(start: EpisodeMarker, end: EpisodeMarker)
    }

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

        // 4. Episode filter (if configured)
        if !source.episodeFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !matchesEpisodeFilter(title: item.title, filter: source.episodeFilter) {
                return false
            }
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

    private func matchesEpisodeFilter(title: String, filter: String) -> Bool {
        let normalized = filter
            .replacingOccurrences(of: "(?i)\\bor\\b", with: ";", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var rules: [EpisodeRule] = []
        for part in normalized.split(separator: ";") {
            let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            // Allow space-separated tokens such as "01 02 03"
            let candidates = text.contains("-")
                ? [text]
                : text.split(whereSeparator: \.isWhitespace).map(String.init)

            for candidate in candidates {
                if let rule = parseEpisodeRule(candidate) {
                    rules.append(rule)
                }
            }
        }

        // Invalid filter text should not change current behavior.
        if rules.isEmpty {
            return true
        }

        guard let itemMarker = extractEpisodeMarker(from: title) else {
            return false
        }

        return rules.contains { rule in
            matches(rule: rule, item: itemMarker)
        }
    }

    private func extractEpisodeMarker(from title: String) -> EpisodeMarker? {
        // e.g. S01E10 / s1e10 / S01-E10
        if let match = firstMatch(in: title, pattern: #"(?i)\bS(\d{1,2})[ ._-]?E(\d{1,3})\b"#),
           let season = captureInt(match: match, group: 1, in: title),
           let episode = captureInt(match: match, group: 2, in: title) {
            return EpisodeMarker(season: season, episode: episode)
        }

        // e.g. E12 / EP12
        if let match = firstMatch(in: title, pattern: #"(?i)\bE(?:P)?[ ._-]?(\d{1,3})\b"#),
           let episode = captureInt(match: match, group: 1, in: title) {
            return EpisodeMarker(season: nil, episode: episode)
        }

        // e.g. "... - 25 (720p)"
        if let match = firstMatch(in: title, pattern: #"(?i)(?:\s-\s|\s)(\d{1,3})(?=\s*[\(\[]|$)"#),
           let episode = captureInt(match: match, group: 1, in: title) {
            return EpisodeMarker(season: nil, episode: episode)
        }

        return nil
    }

    private func parseEpisodeRule(_ text: String) -> EpisodeRule? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let left = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let start = parseEpisodeMarker(left, inheritedSeason: nil),
                      let end = parseEpisodeMarker(right, inheritedSeason: start.season) else {
                    return nil
                }
                return .range(start: start, end: end)
            }
        }

        guard let marker = parseEpisodeMarker(trimmed, inheritedSeason: nil) else { return nil }
        return .single(marker)
    }

    private func parseEpisodeMarker(_ text: String, inheritedSeason: Int?) -> EpisodeMarker? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.isEmpty { return nil }

        if let match = firstMatch(in: normalized, pattern: #"^S(\d{1,2})E(\d{1,3})$"#),
           let season = captureInt(match: match, group: 1, in: normalized),
           let episode = captureInt(match: match, group: 2, in: normalized) {
            return EpisodeMarker(season: season, episode: episode)
        }

        if let match = firstMatch(in: normalized, pattern: #"^E?(\d{1,3})$"#),
           let episode = captureInt(match: match, group: 1, in: normalized) {
            return EpisodeMarker(season: inheritedSeason, episode: episode)
        }

        return nil
    }

    private func matches(rule: EpisodeRule, item: EpisodeMarker) -> Bool {
        switch rule {
        case .single(let marker):
            if let season = marker.season, item.season != season {
                return false
            }
            return item.episode == marker.episode

        case .range(let start, let end):
            let rangeSeason = start.season ?? end.season
            if let season = rangeSeason, item.season != season {
                return false
            }

            // Cross-season ranges are not supported yet.
            if let startSeason = start.season, let endSeason = end.season, startSeason != endSeason {
                return false
            }

            let lower = min(start.episode, end.episode)
            let upper = max(start.episode, end.episode)
            return (lower...upper).contains(item.episode)
        }
    }

    private func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private func captureInt(match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return Int(text[range])
    }
}
