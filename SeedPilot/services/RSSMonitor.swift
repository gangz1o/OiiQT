//
//  RSSMonitor.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class RSSMonitor {
    static let shared = RSSMonitor()

    var lastCheckTime: Date?
    var isChecking: Bool = false
    
    private var timerTask: Task<Void, Never>?

    // MARK: - Auto Refresh Timer

    /// Start or restart the auto-refresh timer based on user setting.
    /// Call this on app launch and whenever the setting changes.
    func startAutoRefresh(sources: [RSSFeedSource], context: ModelContext, appStateManager: AppStateManager?) {
        stopAutoRefresh()
        
        let intervalMinutes = UserDefaults.standard.integer(forKey: "rssRefreshInterval")
        guard intervalMinutes > 0 else {
            print("[RSSMonitor] Auto-refresh disabled (interval = 0)")
            return
        }
        
        let intervalNanos = UInt64(intervalMinutes) * 60 * 1_000_000_000
        print("[RSSMonitor] Auto-refresh started: every \(intervalMinutes) min")
        
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }
                await self?.checkFeeds(sources: sources, context: context, appStateManager: appStateManager)
            }
        }
    }
    
    func stopAutoRefresh() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Feed Check

    /// Fetch all enabled RSS sources, deduplicate items, and auto-download if rules match.
    @MainActor
    func checkFeeds(sources: [RSSFeedSource], context: ModelContext, appStateManager: AppStateManager?) async {
        guard !isChecking else { return }
        isChecking = true
        print("[RSSMonitor] Starting check for \(sources.count) sources...")

        for source in sources where source.isEnabled {
            do {
                let fetchedItems = try await RSSManager.shared.fetchRSS(source: source)
                
                let existingByLink = Dictionary(source.items.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
                let existingByTitle = Dictionary(source.items.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })

                var newItems: [RSSItem] = []
                
                for item in fetchedItems {
                    if existingByLink[item.link] != nil { continue }
                    
                    if let oldItem = existingByTitle[item.title], oldItem.link != item.link {
                        oldItem.link = item.link
                        oldItem.isDownloaded = false
                    } else {
                        item.source = source
                        context.insert(item)
                        newItems.append(item)
                    }
                }
                source.lastUpdated = Date()
                
                // Auto-download: check new items against rules
                if source.autoDownload, let asm = appStateManager {
                    for item in newItems {
                        if RSSRuleEngine.shared.matchesRule(item: item, source: source) && !item.isDownloaded {
                            print("[RSSMonitor] Auto-download match: \(item.title)")
                            let options = AddTorrentOptions(
                                savePath: source.savePath,
                                category: source.category,
                                isPaused: source.addPaused,
                                isFirstLastPiecePriority: source.priority > 0
                            )
                            do {
                                try await asm.addTorrents([item.link], options: options, to: source.targetServerId)
                                item.isDownloaded = true
                            } catch {
                                print("[RSSMonitor] Auto-download failed: \(error)")
                            }
                        }
                    }
                }
                
                if !newItems.isEmpty {
                    print("[RSSMonitor] \(source.name): \(newItems.count) new items")
                }
            } catch {
                print("[RSSMonitor] Failed to fetch \(source.name): \(error)")
            }
        }

        lastCheckTime = Date()
        isChecking = false
        print("[RSSMonitor] Check complete.")
    }
    
    // MARK: - Single Source Refresh
    
    /// Refresh a single RSS source (used by "立即刷新" button).
    @MainActor
    func refreshSource(_ source: RSSFeedSource, context: ModelContext) async {
        do {
            let fetchedItems: [RSSItem]
            if source.url.contains("example.com") || source.url.contains("test") {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                fetchedItems = RSSItem.examples
            } else {
                fetchedItems = try await RSSManager.shared.fetchRSS(source: source)
            }

            let existingByLink = Dictionary(source.items.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
            let existingByTitle = Dictionary(source.items.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })

            for item in fetchedItems {
                if existingByLink[item.link] != nil { continue }
                if let oldItem = existingByTitle[item.title], oldItem.link != item.link {
                    oldItem.link = item.link
                    oldItem.isDownloaded = false
                } else {
                    item.source = source
                    context.insert(item)
                }
            }
            source.lastUpdated = Date()
        } catch {
            print("[RSSMonitor] Refresh failed for \(source.name): \(error)")
        }
    }
}
