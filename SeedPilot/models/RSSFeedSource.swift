//
//  RSSFeedSource.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

struct RSSFeedSource: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var isEnabled: Bool
    var lastUpdated: Date
    var autoDownload: Bool
    var unreadCount: Int = 0 // Added for the badge
    var faviconUrl: String?

    // Rule Engine Properties
    var includeKeywords: [String] = []
    var excludeKeywords: [String] = []
    var minSizeGB: Double? = nil
    var maxSizeGB: Double? = nil
    var targetServerId: UUID? = nil

    // Mock data for preview
    static let examples: [RSSFeedSource] = [
        RSSFeedSource(name: "M-Team Free", url: "https://kp.m-team.cc/rss.php", isEnabled: true, lastUpdated: Date(), autoDownload: true, unreadCount: 24, faviconUrl: "https://kp.m-team.cc/favicon.ico", includeKeywords: ["4K", "REMUX"], excludeKeywords: ["720p"]),
        RSSFeedSource(name: "AudiosNews", url: "https://audionews.org/rss.php", isEnabled: true, lastUpdated: Date().addingTimeInterval(-3600), autoDownload: false, unreadCount: 5, faviconUrl: "https://audionews.org/favicon.ico"),
        RSSFeedSource(name: "Nyaa.si", url: "https://nyaa.si/?page=rss", isEnabled: true, lastUpdated: Date().addingTimeInterval(-86400), autoDownload: true, unreadCount: 0, faviconUrl: "https://nyaa.si/static/favicon.png")
    ]
}
