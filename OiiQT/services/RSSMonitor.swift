//
//  RSSMonitor.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/16.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
class RSSMonitor {
    static let shared = RSSMonitor()

    var lastCheckTime: Date? {
        get { UserDefaults.standard.object(forKey: "rssLastCheckTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "rssLastCheckTime") }
    }
    var isChecking: Bool = false
    
    private var timer: Timer?

    // MARK: - Auto Refresh Timer

    /// Start the 60-second polling timer.
    /// Refresh timing is based on physical elapsed time (lastCheckTime), not on when this is called.
    /// Safe to call multiple times — existing timer is replaced without affecting refresh schedule.
    func startAutoRefresh(sources: [RSSFeedSource], context: ModelContext, appStateManager: AppStateManager?) {
        stopAutoRefresh()

        let intervalMinutes = UserDefaults.standard.integer(forKey: "rssRefreshInterval")
        guard intervalMinutes > 0 else {
            print("[RSSMonitor] Auto-refresh disabled (interval = 0)")
            return
        }

        print("[RSSMonitor] Auto-refresh started: poll every 60s, target=\(intervalMinutes)min")

        // Check immediately on start (handles first launch and app-reopen)
        checkIfOverdue(context: context, appStateManager: appStateManager)

        // Poll every 60s — actual refresh decision based on physical elapsed time
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkIfOverdue(context: context, appStateManager: appStateManager)
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    /// Check if enough physical time has elapsed since last check.
    /// If overdue, triggers a feed check. Never resets the polling timer.
    func checkIfOverdue(context: ModelContext, appStateManager: AppStateManager?) {
        let intervalMinutes = UserDefaults.standard.integer(forKey: "rssRefreshInterval")
        guard intervalMinutes > 0 else { return }

        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let elapsed = lastCheckTime.map { Date().timeIntervalSince($0) } ?? intervalSeconds
        let isOverdue = elapsed >= intervalSeconds

        print("[RSSMonitor] Poll: \(Int(elapsed))s elapsed / \(Int(intervalSeconds))s target, overdue=\(isOverdue)")
        guard isOverdue else { return }

        Task { @MainActor in
            await self.checkFeeds(context: context, appStateManager: appStateManager)
        }
    }

    // MARK: - Feed Check

    /// Fetch all enabled RSS sources, deduplicate items, and auto-download if rules match.
    @MainActor
    func checkFeeds(context: ModelContext, appStateManager: AppStateManager?) async {
        guard !isChecking else {
            print("[RSSMonitor] Already checking, skipping")
            return
        }
        isChecking = true
        defer {
            isChecking = false
            lastCheckTime = Date()
            print("[RSSMonitor] Check complete at \(Date())")
        }

        // Always fetch fresh sources from SwiftData
        let sources: [RSSFeedSource]
        do {
            let descriptor = FetchDescriptor<RSSFeedSource>()
            sources = try context.fetch(descriptor)
        } catch {
            print("[RSSMonitor] Failed to fetch sources from DB: \(error)")
            return
        }
        
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
                    } else if existingByTitle[item.title] == nil {
                        item.source = source
                        context.insert(item)
                        newItems.append(item)
                    }
                }
                source.lastUpdated = Date()
                
                print("[RSSMonitor] \(source.name): fetched=\(fetchedItems.count), new=\(newItems.count)")
                
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
                                try await asm.addTorrents(
                                    [item.link],
                                    options: options,
                                    to: source.targetServerId,
                                    enforcePausedFallback: source.addPaused
                                )
                                item.isDownloaded = true
                                print("[RSSMonitor] Auto-download success: \(item.title)")
                            } catch {
                                print("[RSSMonitor] Auto-download failed: \(error)")
                            }
                        }
                    }
                }
            } catch {
                print("[RSSMonitor] Failed to fetch \(source.name): \(error)")
            }
        }
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
                } else if existingByTitle[item.title] == nil {
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
