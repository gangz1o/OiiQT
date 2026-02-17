//
//  RSSManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation

@Observable
class RSSManager: NSObject, XMLParserDelegate {
    static let shared = RSSManager()

    // Parser State
    private var currentFeedItems: [RSSItem] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentPubDate: String = ""
    private var currentFileSize: String? = nil
    private var currentEnclosureUrl: String? = nil

    private override init() {
        super.init()
    }

    func fetchRSS(source: RSSFeedSource) async throws -> [RSSItem] {
        guard let url = URL(string: source.url) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)

        // Reset state
        currentFeedItems = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        if parser.parse() {
            // Post-process: fix download URLs for NexusPHP-style PT sites
            // where <link> is a details page and the actual download URL
            // needs to be constructed using passkey from the RSS source URL
            fixDownloadLinks(items: currentFeedItems, sourceUrl: source.url)
            return currentFeedItems
        } else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
    }
    
    /// For NexusPHP-based PT sites: transform details page URLs into download URLs.
    /// - If the item already has a proper download/magnet link (from enclosure), skip it.
    /// - If the link contains "details.php", replace with "download.php" and append passkey from source URL.
    /// - If source URL has no passkey, leave the link as-is.
    private func fixDownloadLinks(items: [RSSItem], sourceUrl: String) {
        // Extract passkey from the RSS subscription URL
        guard let sourceComponents = URLComponents(string: sourceUrl),
              let passkey = sourceComponents.queryItems?.first(where: { $0.name == "passkey" })?.value,
              !passkey.isEmpty else {
            return
        }
        
        for item in items {
            // Skip items that already have a proper download link (from enclosure, magnet, or .torrent)
            if item.link.contains("download.php") || item.link.hasPrefix("magnet:") || item.link.hasSuffix(".torrent") {
                continue
            }
            
            // NexusPHP pattern: details.php?id=xxx → download.php?id=xxx&passkey=yyy
            if item.link.contains("details.php") {
                guard var components = URLComponents(string: item.link) else { continue }
                components.path = components.path.replacingOccurrences(of: "details.php", with: "download.php")
                
                var queryItems = components.queryItems ?? []
                // Remove non-essential params like "hit" that details pages may have
                queryItems.removeAll { $0.name == "hit" }
                // Add passkey
                if !queryItems.contains(where: { $0.name == "passkey" }) {
                    queryItems.append(URLQueryItem(name: "passkey", value: passkey))
                }
                components.queryItems = queryItems
                
                if let newUrl = components.url?.absoluteString {
                    item.link = newUrl
                }
            }
        }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
            currentFileSize = nil
            currentEnclosureUrl = nil
        }

        // Extract download URL and file size from enclosure
        if elementName == "enclosure" {
            if let enclosureUrl = attributeDict["url"], !enclosureUrl.isEmpty {
                currentEnclosureUrl = enclosureUrl
            }
            if let lengthStr = attributeDict["length"], let bytes = Int64(lengthStr) {
                currentFileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "pubDate":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // Prefer enclosure URL (actual torrent/magnet link) over <link> (often just a web page URL)
            let downloadLink = currentEnclosureUrl ?? currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: downloadLink,
                pubDate: parseDate(currentPubDate) ?? Date(),
                isDownloaded: false,
                sourceName: nil,
                fileSize: currentFileSize,
                tmdbPosterUrl: nil
            )
            currentFeedItems.append(item)
        }
    }

    // Helper to parse RSS dates (RFC 822)
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Try standard RSS format
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: dateString)
    }
}
