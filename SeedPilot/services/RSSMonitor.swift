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

    var lastCheckTime: Date? {
        get { UserDefaults.standard.object(forKey: "rssLastCheckTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "rssLastCheckTime") }
    }
    var isChecking: Bool = false
    
    private var timer: Timer?

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
        
        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        print("[RSSMonitor] Auto-refresh starting: every \(intervalMinutes) min")
        
        // Immediate overdue check
        let isOverdue: Bool
        if let lastCheck = lastCheckTime {
            let elapsed = Date().timeIntervalSince(lastCheck)
            isOverdue = elapsed >= intervalSeconds
            print("[RSSMonitor] Last check \(Int(elapsed))s ago, overdue=\(isOverdue)")
        } else {
            isOverdue = true
            print("[RSSMonitor] Never checked before, overdue=true")
        }
        
        if isOverdue {
            Task { @MainActor in
                await self.checkFeeds(context: context, appStateManager: appStateManager)
            }
        }
        
        // Foundation Timer on main RunLoop — most reliable timer on iOS
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            print("[RSSMonitor] ⏰ Timer fired at \(Date())")
            Task { @MainActor in
                await self?.checkFeeds(context: context, appStateManager: appStateManager)
            }
        }
        // Ensure timer fires even during scroll/tracking
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        print("[RSSMonitor] ✅ Timer scheduled on main RunLoop, interval=\(Int(intervalSeconds))s")
    }
    
    func stopAutoRefresh() {
        if timer != nil {
            print("[RSSMonitor] Stopping previous timer")
        }
        timer?.invalidate()
        timer = nil
    }

    /// Only check if overdue and fetch — does NOT reset the running timer.
    /// Call this when app returns to foreground.
    func checkIfOverdue(context: ModelContext, appStateManager: AppStateManager?) {
        let intervalMinutes = UserDefaults.standard.integer(forKey: "rssRefreshInterval")
        guard intervalMinutes > 0 else { return }

        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let isOverdue: Bool
        if let lastCheck = lastCheckTime {
            let elapsed = Date().timeIntervalSince(lastCheck)
            isOverdue = elapsed >= intervalSeconds
            print("[RSSMonitor] Foreground check: elapsed=\(Int(elapsed))s, overdue=\(isOverdue)")
        } else {
            isOverdue = true
        }

        guard isOverdue else { return }
        print("[RSSMonitor] Overdue on foreground — checking immediately (timer NOT reset)")
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
