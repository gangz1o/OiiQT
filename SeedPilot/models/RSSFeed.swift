//
//  RSSFeed.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

struct RSSFeed: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var alias: String
    var url: String
    var faviconUrl: String?
    var lastUpdated: Date
    var itemCount: Int
    var autoDownload: Bool

    // Mock data for preview
    static let examples: [RSSFeed] = [
        RSSFeed(alias: "M-Team Free", url: "https://kp.m-team.cc/rss.php", faviconUrl: "https://kp.m-team.cc/favicon.ico", lastUpdated: Date(), itemCount: 12, autoDownload: true),
        RSSFeed(alias: "AudiosNews", url: "https://audionews.org/rss.php", faviconUrl: "https://audionews.org/favicon.ico", lastUpdated: Date().addingTimeInterval(-3600), itemCount: 5, autoDownload: false)
    ]
}
