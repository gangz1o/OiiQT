import Foundation
import SwiftData

@Model
final class RSSItem {
    var id: UUID = UUID()
    var title: String = ""
    var link: String = ""
    var pubDate: Date = Date()
    var isDownloaded: Bool = false
    var sourceName: String? // Optional redundant ref
    var fileSize: String? // e.g., "1.2 GB"
    var tmdbPosterUrl: URL? // TMDB integration

    // Inverse Relationship
    var source: RSSFeedSource?

    init(title: String, link: String, pubDate: Date, isDownloaded: Bool, sourceName: String?, fileSize: String?, tmdbPosterUrl: URL?) {
        self.id = UUID()
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.isDownloaded = isDownloaded
        self.sourceName = sourceName
        self.fileSize = fileSize
        self.tmdbPosterUrl = tmdbPosterUrl
    }

    // Mock data for preview (static function instead of static let for @Model usually safe, but let works in preview contexts sometimes)
    static var examples: [RSSItem] {
        [
            RSSItem(title: "Ubuntu 24.04 LTS Desktop", link: "https://ubuntu.com", pubDate: Date(), isDownloaded: false, sourceName: "Linux ISOs", fileSize: "4.7 GB", tmdbPosterUrl: nil),
            RSSItem(title: "Big Buck Bunny 4K", link: "https://bbb.com", pubDate: Date().addingTimeInterval(-1800), isDownloaded: true, sourceName: "Demo Content", fileSize: "12.5 GB", tmdbPosterUrl: URL(string: "https://image.tmdb.org/t/p/w200/uXDfjJbdP4ijW5hWSBrPrlKpxab.jpg"))
        ]
    }
}
