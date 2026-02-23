//
//  ResolutionExtractor.swift
//  SeedPilot
//

import SwiftUI

struct ResolutionExtractor {
    private static let cacheLock = NSLock()
    private static var badgeCache: [String: ResolutionBadge] = [:]
    private static var noBadgeCache: Set<String> = []

    static func extractBadge(from title: String) -> ResolutionBadge? {
        cacheLock.lock()
        if let cached = badgeCache[title] {
            cacheLock.unlock()
            return cached
        }
        if noBadgeCache.contains(title) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        let lowercasedTitle = title.lowercased()
        let badge: ResolutionBadge?

        if lowercasedTitle.contains("2160p") || lowercasedTitle.contains("4k") || lowercasedTitle.contains("uhd") {
            badge = .ultraHD
        } else if lowercasedTitle.contains("1080p") || lowercasedTitle.contains("1080i") {
            badge = .fullHD
        } else if lowercasedTitle.contains("720p") {
            badge = .hd
        } else {
            badge = nil
        }

        cacheLock.lock()
        if let badge {
            badgeCache[title] = badge
        } else {
            noBadgeCache.insert(title)
        }
        cacheLock.unlock()

        return badge
    }

    static func extractResolution(from title: String) -> (text: String, color: Color)? {
        guard let badge = extractBadge(from: title) else { return nil }
        return (badge.text, badge.color)
    }
}
