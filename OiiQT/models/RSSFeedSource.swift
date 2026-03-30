import Foundation
import SwiftData

@Model
final class RSSFeedSource {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var isEnabled: Bool = true
    var lastUpdated: Date = Date()
    var autoDownload: Bool = false
    var apiKey: String?
    var unreadCount: Int = 0
    var faviconUrl: String?

    // Rule Engine Properties
    var includeKeywords: [String] = []
    var excludeKeywords: [String] = []
    var minSizeGB: Double? = nil
    var maxSizeGB: Double? = nil
    var targetServerId: UUID? = nil

    // V4 Advanced Properties
    var savePath: String = "" // Storage Path
    var category: String = "" // Category/Label
    var addPaused: Bool = false // Start Paused?
    var priority: Int = 0 // 0: Normal, 1: High, -1: Low
    var episodeFilter: String = "" // e.g. "01-12; 15"

    // Relationship
    @Relationship(deleteRule: .cascade, inverse: \RSSItem.source)
    var items: [RSSItem] = []

    init(
        name: String,
        url: String,
        isEnabled: Bool,
        lastUpdated: Date,
        autoDownload: Bool,
        unreadCount: Int,
        faviconUrl: String?,
        apiKey: String? = nil,
        includeKeywords: [String] = [],
        excludeKeywords: [String] = []
    ) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.lastUpdated = lastUpdated
        self.autoDownload = autoDownload
        self.apiKey = apiKey
        self.unreadCount = unreadCount
        self.faviconUrl = faviconUrl
        self.includeKeywords = includeKeywords
        self.excludeKeywords = excludeKeywords
    }

    // Mock data for preview
    static var examples: [RSSFeedSource] {
        [
            RSSFeedSource(name: "M-Team Free", url: "https://kp.m-team.cc/rss.php", isEnabled: true, lastUpdated: Date(), autoDownload: true, unreadCount: 24, faviconUrl: "https://kp.m-team.cc/favicon.ico", includeKeywords: ["4K", "REMUX"], excludeKeywords: ["720p"]),
            RSSFeedSource(name: "AudiosNews", url: "https://audionews.org/rss.php", isEnabled: true, lastUpdated: Date().addingTimeInterval(-3600), autoDownload: false, unreadCount: 5, faviconUrl: "https://audionews.org/favicon.ico"),
            RSSFeedSource(name: "Nyaa.si", url: "https://nyaa.si/?page=rss", isEnabled: true, lastUpdated: Date().addingTimeInterval(-86400), autoDownload: true, unreadCount: 0, faviconUrl: "https://nyaa.si/static/favicon.png")
        ]
    }

    /// Runtime favicon resolver with M-Team override for rss subdomain feeds.
    var resolvedFaviconURLString: String? {
        if url.lowercased().contains("m-team.cc") {
            return "https://m-team.cc/favicon.ico"
        }

        if let faviconUrl {
            let trimmed = faviconUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let feedURL = URL(string: url),
              let scheme = feedURL.scheme,
              let host = feedURL.host() else {
            return nil
        }
        return "\(scheme)://\(host)/favicon.ico"
    }
}
