//
//  RSSFeedDetailView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

//
//  RSSFeedDetailView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import SwiftData
import UIKit

struct RSSFeedDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appStateManager

    @Bindable var source: RSSFeedSource

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingEditRules = false

    // Computed sorted items from relationship
    var sortedItems: [RSSItem] {
        source.items.sorted { $0.pubDate > $1.pubDate }
    }

    var body: some View {
        List {
            if isLoading && sortedItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage, sortedItems.isEmpty {
                ContentUnavailableView(
                    LanguageManager.shared.localized("Unable to Load Feed"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ForEach(sortedItems) { item in
                    RSSItemRow(item: item, source: source)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task {
                                    // Swipe download same as tap
                                    await downloadItem(item)
                                }
                            } label: {
                                Label(LanguageManager.shared.localized("Download"), systemImage: "arrow.down.circle")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(source.name)
        .toolbar {
             ToolbarItem(placement: .topBarTrailing) {
                 Button {
                     showingEditRules = true
                 } label: {
                     Image(systemName: "gearshape")
                 }
             }
         }
         .sheet(isPresented: $showingEditRules) {
             EditRSSRuleView(source: source)
         }
        .refreshable {
            await loadData()
        }
        .task {
            // Refresh Task List to sync download status
            await appStateManager.refreshData()

            // Initial load if empty
            if sortedItems.isEmpty {
                await loadData()
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            // Fetch from network (returns unpersisted model objects)
            let fetchedItems: [RSSItem]
            if source.url.contains("example.com") || source.url.contains("test") {
                 try await Task.sleep(nanoseconds: 1_000_000_000) // fake delay
                 fetchedItems = RSSItem.examples
            } else {
                 fetchedItems = try await RSSManager.shared.fetchRSS(source: source)
            }

            // Deduplicate and Persist
            await MainActor.run {
                let existingByLink = Dictionary(source.items.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
                let existingByTitle = Dictionary(source.items.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })

                for item in fetchedItems {
                    if existingByLink[item.link] != nil {
                        // Exact link match — already exists, skip
                        continue
                    }
                    
                    if let oldItem = existingByTitle[item.title], oldItem.link != item.link {
                        // Same title but different link — old item had wrong URL, update it
                        oldItem.link = item.link
                        oldItem.isDownloaded = false
                    } else {
                        // Truly new item
                        item.source = source
                        modelContext.insert(item)
                    }
                }
                source.lastUpdated = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
            // Fallback to mock for demo if network fails and list is empty
            if sortedItems.isEmpty {
                // Could retry or show empty
            }
        }
        isLoading = false
    }

    private func downloadItem(_ item: RSSItem) async {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        let options = AddTorrentOptions(
            savePath: source.savePath,
            category: source.category,
            isPaused: source.addPaused,
            isFirstLastPiecePriority: source.priority > 0
        )

        do {
            try await appStateManager.addTorrents([item.link], options: options, to: source.targetServerId)
            await MainActor.run {
                withAnimation {
                    item.isDownloaded = true
                }
                generator.notificationOccurred(.success)
            }
        } catch {
            print("Download failed: \(error)")
            await MainActor.run {
                 generator.notificationOccurred(.error)
            }
        }
    }

}

struct RSSItemRow: View {
    let item: RSSItem
    let source: RSSFeedSource

    @Environment(AppStateManager.self) private var appStateManager

    // Pro Features
    @AppStorage("isProUser") private var isProUser = false
    @AppStorage("tmdbPosterEnabled") private var tmdbPosterEnabled = false

    // State (Transient)
    @State private var isDownloading = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Poster/Favicon (Pro Guarded)
            Group {
                if isProUser && tmdbPosterEnabled, let posterUrl = item.tmdbPosterUrl {
                    SimpleCachedImage(url: posterUrl)
                        .scaleEffect(1.0) // Placeholder to match type expectation if needed, or just let SimpleCachedImage invoke resizable
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackIcon
                }
            }
            .frame(width: 40, height: 60)
            .clipped() // Ensure fill doesn't overflow
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Center: Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let size = item.fileSize {
                        Text(size)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(item.pubDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: Download Action
            Button {
                triggerDownload()
            } label: {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else if item.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || item.isDownloaded)
        }
        .padding(.vertical, 4)
        .onAppear {
            checkDownloadStatus()
        }
    }

    // MARK: - Subviews

    private var fallbackIcon: some View {
        RSSFaviconImage(url: URL(string: source.resolvedFaviconURLString ?? ""))
            .aspectRatio(contentMode: .fit)
    }

    // MARK: - Actions

    private func checkDownloadStatus() {
        // Optimistic check against AppStateManager's task list
        // If found, update the persistent model
        if !item.isDownloaded {
            if appStateManager.allTasks.contains(where: {
                item.link.lowercased().contains($0.id.lowercased()) ||
                $0.name == item.title
            }) {
                item.isDownloaded = true
                // Note: SwiftData auto-saves changes to managed objects
            }
        }
    }

    private func triggerDownload() {
        guard !isDownloading && !item.isDownloaded else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        isDownloading = true

        Task {
            // Simulate minimal delay for UI feedback
            try? await Task.sleep(nanoseconds: 200_000_000)

            do {
                // Construct Options from Source Rules
                let options = AddTorrentOptions(
                    savePath: source.savePath,
                    category: source.category,
                    isPaused: source.addPaused,
                    isFirstLastPiecePriority: source.priority > 0
                )

                try await appStateManager.addTorrents([item.link], options: options, to: source.targetServerId)

                await MainActor.run {
                    withAnimation {
                        isDownloading = false
                        item.isDownloaded = true
                    }
                    generator.notificationOccurred(.success)
                }
            } catch {
                print("Failed to download: \(error)")
                await MainActor.run {
                    isDownloading = false
                    generator.notificationOccurred(.error)
                    // Optional: Show toast or alert here
                }
            }
        }
    }
}
