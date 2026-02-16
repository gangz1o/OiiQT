//
//  RSSFeedDetailView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

struct RSSFeedDetailView: View {
    @State var source: RSSFeedSource
    @State private var items: [RSSItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingEditRules = false

    var body: some View {
        List {
            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage, items.isEmpty {
                ContentUnavailableView("无法加载订阅", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ForEach(items) { item in
                    HStack(alignment: .center, spacing: 12) {
                        // Left: Poster/Favicon
                        AsyncImage(url: item.tmdbPosterUrl ?? URL(string: source.faviconUrl ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                if let _ = item.tmdbPosterUrl {
                                    ProgressView()
                                } else {
                                    // Fallback to source icon logic or generic
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 40, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

                        // Right: Status
                        Image(systemName: item.isDownloaded ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                            .font(.title3)
                            .foregroundStyle(item.isDownloaded ? .green : .blue)
                            .onTapGesture {
                                // Trigger download
                            }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .leading) {
                        Button {
                            // TODO: Add download logic
                        } label: {
                            Label("下载", systemImage: "arrow.down.circle")
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
             EditRSSRuleView(source: $source)
         }
        .refreshable {
            await loadData()
        }
        .task {
            // Initial load if empty
            if items.isEmpty {
                await loadData()
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            // In a real app, we might check if 'source' has a mocked URL first
            // For now, if it's a mock source, just load mock items unless it's a real URL
            if source.url.contains("example.com") || source.url.contains("test") {
                 try await Task.sleep(nanoseconds: 1_000_000_000) // fake delay
                 items = RSSItem.examples
            } else {
                 items = try await RSSManager.shared.fetchRSS(source: source)
            }
        } catch {
            errorMessage = error.localizedDescription
            // Fallback to mock for demo if network fails
            items = RSSItem.examples
        }
        isLoading = false
    }
}
