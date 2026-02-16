//
//  SeedPilotParser.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation

struct SeedPilotMetadata {
    let title: String
    let year: String?
    let season: String?
    let quality: String?
    let englishTitle: String?  // Fallback English title for TMDB search
    
    init(title: String, year: String?, season: String?, quality: String?, englishTitle: String? = nil) {
        self.title = title
        self.year = year
        self.season = season
        self.quality = quality
        self.englishTitle = englishTitle
    }
}

struct SeedPilotParser {

    // MARK: - Regex Patterns (The Wall)

    // Season/Episode: S01, S01E01, E01
    private static let seasonPattern = #"\b[Ss]\d+([Ee]\d+)?\b|\b[Ee]\d+\b"#

    // Resolution: 4K, 2160p, 1080p, 720p
    private static let resolutionPattern = #"\b(4[Kk]|2160[Pp]|1080[ipIP]|720[Pp])\b"#

    // Platform: YOUKU, iQIYI, MGTV, Bilibili, Netflix, NF, DSNP, Disney, AMZN
    private static let platformPattern = #"\b(YOUKU|iQIYI|MGTV|Bilibili|Netflix|NF|DSNP|Disney|AMZN)\b"#

    // Specs: WEB-DL, BluRay, H.264, HEVC, AAC, etc.
    private static let specsPattern = #"\b(WEB[- ]?DL|WebRip|BluRay|Remux|H[.\s]?26[45]|HEVC|AVC|AAC|AC3|DDP|DTS|TrueHD|Atmos)\b"#

    // Year: 19xx or 20xx (to extract year)
    private static let yearPattern = #"\b(19|20)\d{2}\b"#

    // TV Stations (Blacklist prefix)
    private static let tvStationPattern = #"\b(KBS\d?|SBS|MBC|TVN|JTBC)\b"#

    // MARK: - API

    static func parse(_ rawName: String) -> SeedPilotMetadata {
        // 0. Pre-extract: Chinese text in brackets at end of title
        //    Many PT sites: "Swallowed Star S01 2020...[吞噬星空]" or "[HHWEB][吞噬星空]..."
        let bracketChinese = extractChineseFromBrackets(rawName)
        
        // 1. Preprocessing: Replace dots with spaces, consolidate spaces
        var cleaned = rawName.replacingOccurrences(of: ".", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        // Combine multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // 2. Remove Noise (Blacklist Prefix)
        if let regex = try? NSRegularExpression(pattern: "^\(tvStationPattern)", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: " ")
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }

        // 3. Anchor Truncation (Find earliest technical tag)
        let anchorPatterns = [seasonPattern, resolutionPattern, platformPattern, specsPattern, yearPattern]
        var cutIndex = cleaned.endIndex

        var yearFound: String?
        var seasonFound: String?
        var qualityFound: String?

        func checkMatch(_ pattern: String, in text: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

            for result in results {
                if let range = Range(result.range, in: text) {
                    if range.lowerBound < cutIndex {
                        cutIndex = range.lowerBound
                    }
                    let matchedString = String(text[range])
                    if pattern == yearPattern { yearFound = matchedString }
                    if pattern == seasonPattern { seasonFound = matchedString }
                    if pattern == resolutionPattern { qualityFound = matchedString }
                }
            }
        }

        for p in anchorPatterns {
            checkMatch(p, in: cleaned)
        }

        // 4. Extract Title (portion before first anchor)
        var title = String(cleaned[..<cutIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "-_[]()"))
        title = title.trimmingCharacters(in: .whitespaces)
        
        // Also try to extract year from full raw name if not found in cleaned prefix
        if yearFound == nil {
            if let range = rawName.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
                yearFound = String(rawName[range])
            }
        }

        // 5. Chinese Prioritization
        // Priority: bracket Chinese > inline Chinese > English title
        if let bracketCN = bracketChinese, !bracketCN.isEmpty {
            // Use Chinese name from brackets (most reliable for PT sites)
            title = bracketCN
        } else if hasChineseCharacters(title) {
            let chinesePart = extractChinese(title)
            if !chinesePart.isEmpty {
                title = chinesePart
            }
        }
        // Keep English title as fallback (stored in englishTitle)
        let englishTitle = String(cleaned[..<cutIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_[]()"))
            .trimmingCharacters(in: .whitespaces)

        if title.isEmpty { title = rawName }

        return SeedPilotMetadata(title: title, year: yearFound, season: seasonFound, quality: qualityFound, englishTitle: englishTitle != title ? englishTitle : nil)
    }

    // MARK: - Helpers
    
    /// Extract Chinese text from square brackets in the raw title.
    /// PT sites often append Chinese names: "English Title S01 2020...[中文名]" or "[Group][中文名]..."
    private static func extractChineseFromBrackets(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]*[\u{4e00}-\u{9fa5}][^\\]]*)\\]", options: []) else { return nil }
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        // Find the bracket content that is primarily Chinese (filter out tags like [1080p], [HHWEB])
        var bestMatch: String?
        var bestChineseCount = 0
        
        for result in results {
            guard result.numberOfRanges > 1,
                  let range = Range(result.range(at: 1), in: text) else { continue }
            let content = String(text[range]).trimmingCharacters(in: .whitespaces)
            
            // Count Chinese characters
            let chineseCount = content.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FA5 }.count
            
            // Must have at least 2 Chinese chars and be primarily Chinese (>50%)
            if chineseCount >= 2 && chineseCount > bestChineseCount {
                bestChineseCount = chineseCount
                bestMatch = content
            }
        }
        
        return bestMatch
    }

    private static func hasChineseCharacters(_ text: String) -> Bool {
        return text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private static func extractChinese(_ text: String) -> String {
        // Extract all Chinese characters and join them?
        // Sometimes "人世间 第1季" -> "人世间"
        // Let's keep spaces between Chinese blocks if needed?
        // Or just extract the first longest consecutive Chinese block?
        // Try to match standard Chinese title patterns.
        // For simplicity: Join all Han characters? No, that might merge "Movie 1" and "Movie 2" if name list.
        // Usually: "English Title 中文标题" -> "中文标题"
        // "中文标题 English Title" -> "中文标题"

        // Strategy: Remove non-Chinese, non-number, non-space?
        // Keeping it simple: Extract sequences of Han characters (and maybe numbers inside).
        // Let's iterate and build.

        guard let regex = try? NSRegularExpression(pattern: "[\u{4e00}-\u{9fa5}]+", options: []) else { return "" }
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        let matches = results.compactMap { result -> String? in
            guard let range = Range(result.range, in: text) else { return nil }
            return String(text[range])
        }

        // Return the longest Chinese match, or joined?
        // "长津湖 The Battle..." -> "长津湖"
        // "One Piece 海贼王" -> "海贼王"
        // "海贼王 S01" -> "海贼王"
        // If multiple matches? "卧虎藏龙 Crouching Tiger" -> "卧虎藏龙"

        return matches.sorted { $0.count > $1.count }.first ?? ""
    }
}
