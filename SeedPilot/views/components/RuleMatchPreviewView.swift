//
//  RuleMatchPreviewView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import SwiftData

struct RuleMatchPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let source: RSSFeedSource

    @State private var mockItems: [RSSItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(LanguageManager.shared.localized("This preview shows simulated RSS entries and whether they match the current rules."))) {
                    if mockItems.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(mockItems) { item in
                            RuleMatchRow(item: item, source: source)
                        }
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Rule Match Test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Close")) {
                        dismiss()
                    }
                }
            }
            .task {
                generateMockItems()
            }
        }
    }

    private func generateMockItems() {
        // Simulate a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.mockItems = [
                RSSItem(title: "[NGB] Shang hai Tan (1980) 1080p x265 AAC-Mandarin", link: "1", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "12.5 GB", tmdbPosterUrl: nil),
                RSSItem(title: "[Hares] The Matrix (1999) 4K REMUX HDR TrueHD", link: "2", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "60.2 GB", tmdbPosterUrl: nil),
                RSSItem(title: "[Erai-raws] One Piece - 1080 [1080p].mkv", link: "3", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "1.4 GB", tmdbPosterUrl: nil),
                RSSItem(title: "[SubsPlease] Jujutsu Kaisen - 25 (720p) [A3F12].mkv", link: "4", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "500 MB", tmdbPosterUrl: nil),
                RSSItem(title: "My.Neighbor.Totoro.1988.1080p.BluRay.x264-Wiki", link: "5", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "8.1 GB", tmdbPosterUrl: nil),
                RSSItem(title: "[HorribleSubs] Boruto - Naruto Next Generations - 120 [480p].mkv", link: "6", pubDate: Date(), isDownloaded: false, sourceName: source.name, fileSize: "150 MB", tmdbPosterUrl: nil)
            ]
        }
    }
}

struct RuleMatchRow: View {
    let item: RSSItem
    let source: RSSFeedSource

    var isMatch: Bool {
        RSSRuleEngine.shared.matchesRule(item: item, source: source)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status Icon
            Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(isMatch ? .green : .gray.opacity(0.3))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isMatch ? .primary : .secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let size = item.fileSize {
                        Text(size)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }

                    if isMatch {
                        Text(LanguageManager.shared.localized("Matched"))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text(LanguageManager.shared.localized("Filtered"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isMatch ? 1.0 : 0.6)
        .listRowBackground(isMatch ? Color.green.opacity(0.05) : Color.clear)
    }
}
