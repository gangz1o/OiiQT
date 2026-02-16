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

    private override init() {
        super.init()
    }

    func fetchRSS(source: RSSFeedSource) async throws -> [RSSItem] {
        guard let url = URL(string: source.url) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Reset state
        currentFeedItems = []

        let parser = XMLParser(data: data)
        parser.delegate = self

        if parser.parse() {
            return currentFeedItems
        } else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
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
        }

        // Try to extract file size from enclosure
        if elementName == "enclosure", let lengthStr = attributeDict["length"] {
            if let bytes = Int64(lengthStr) {
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
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: parseDate(currentPubDate) ?? Date(),
                isDownloaded: false, // Default
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
