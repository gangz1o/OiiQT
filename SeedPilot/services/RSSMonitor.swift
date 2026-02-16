//
//  RSSMonitor.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation
import SwiftData

@Observable
class RSSMonitor {
    static let shared = RSSMonitor()

    var lastCheckTime: Date?
    var isChecking: Bool = false

    // Mock Background Check
    func checkFeeds(sources: [RSSFeedSource]) async {
        guard !isChecking else { return }
        isChecking = true

        print("RSSMonitor: Starting background check...")

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        for source in sources where source.autoDownload {
            // In a real app, we'd fetch XML here.
            // For now, we simulate finding a "New Item" using the mock generator
            // and checking it against the rules.

            let mockItem = RSSItem(
                title: "[MockGroup] New Movie 2024 1080p REMUX", // Keywords: 1080p, REMUX
                link: "https://example.com/torrent",
                pubDate: Date(),
                isDownloaded: false,
                sourceName: source.name,
                fileSize: "15 GB" // Size: 15
            )

            if RSSRuleEngine.shared.matches(item: mockItem, source: source) {
                print("RSSMonitor: MATCH FOUND! \(mockItem.title)")
                print("RSSMonitor: Triggering download to server ID: \(String(describing: source.targetServerId))")
                // TODO: Trigger actual download API
            } else {
                print("RSSMonitor: Item ignored by rules: \(mockItem.title)")
            }
        }

        lastCheckTime = Date()
        isChecking = false
        print("RSSMonitor: Check complete.")
    }
}
