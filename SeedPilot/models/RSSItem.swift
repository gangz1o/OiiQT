//
//  RSSItem.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

struct RSSItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var link: String
    var pubDate: Date
    var isDownloaded: Bool
    var sourceName: String? // Optional reference to source
    var fileSize: String? // e.g., "1.2 GB"
    var tmdbPosterUrl: URL? // TMDB integration

    static let examples: [RSSItem] = [
        RSSItem(title: "Ubuntu 24.04 LTS Desktop", link: "https://ubuntu.com", pubDate: Date(), isDownloaded: false, sourceName: "Linux ISOs", fileSize: "4.7 GB", tmdbPosterUrl: nil),
        RSSItem(title: "Big Buck Bunny 4K", link: "https://bbb.com", pubDate: Date().addingTimeInterval(-1800), isDownloaded: true, sourceName: "Demo Content", fileSize: "12.5 GB", tmdbPosterUrl: URL(string: "https://image.tmdb.org/t/p/w200/uXDfjJbdP4ijW5hWSBrPrlKpxab.jpg"))
    ]
}
