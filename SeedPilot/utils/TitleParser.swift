//
//  TitleParser.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

struct TitleParser {
    /// Cleans a release title to a simple Movie/Show name for TMDB searching.
    /// Example: "[Group] Movie.Name.2024.1080p.BluRay" -> "Movie Name", "2024"
    static func parse(_ title: String) -> (cleanTitle: String, year: String?) {
        var clean = title

        // 1. Remove content in brackets [...]
        // e.g. [Group] or [1080p]
        clean = clean.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)

        // 2. Remove content in parentheses (...)
        // e.g. (2024) or (WEBRip)
        // We might want to capture year first though.

        // Extract Year if prevalent: 4 digits starting with 19 or 20, surrounded by non-word chars
        var year: String?
        if let range = clean.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            year = String(clean[range])
        }

        clean = clean.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)

        // 3. Remove common release tags (Case insensitive)
        let tags = [
            "S\\d{2}E\\d{2}", "S\\d{2}", "E\\d{2}", // Season/Episode
            "1080p", "720p", "2160p", "4K", "8K",
            "BluRay", "WEB-DL", "WEBRip", "HDTV", "DVDRip",
            "REMUX", "HEVC", "x264", "x265", "AVC", "H.264", "H.265",
            "AAC", "AC3", "DTS", "TrueHD", "Atmos", "FLAC",
            "HDR", "HDR10", "DV", "DoVi",
            "AMZN", "NF", "DSNP", "HMAX" // Streaming services
        ]

        let pattern = tags.joined(separator: "|")
        clean = clean.replacingOccurrences(of: "\\b(\(pattern))\\b", with: "", options: [.regularExpression, .caseInsensitive])

        // 4. Clean formatting characters
        // Replace dots, underscores with spaces
        clean = clean.replacingOccurrences(of: "[._]", with: " ", options: .regularExpression)

        // 5. Remove any remaining years if we extracted it, or if it's just hanging there
        if let y = year {
             clean = clean.replacingOccurrences(of: "\\b\(y)\\b", with: "", options: .regularExpression)
        }

        // 6. Trim duplicate spaces and ends
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback: If we stripped everything (e.g. title was just "1080p"), return original
        if clean.isEmpty {
            return (title, nil)
        }

        return (clean, year)
    }
}
