//
//  ManualMatchView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI

struct ManualMatchView: View {
    let taskName: String
    let taskHash: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var items: [TMDBItem] = []
    @State private var isLoading = false
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var hasSearched = false

    // Timer for debouncing search (optional, or just use onSubmit)
    // User request: "点击搜索键才触发首次请求" (Search button trigger)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar

                // Result List
                if items.isEmpty && !isLoading {
                    if hasSearched {
                        ContentUnavailableView("未找到相关影视", systemImage: "magnifyingglass", description: Text("请尝试更换关键词或检查拼写"))
                    } else {
                        ContentUnavailableView("准备搜索", systemImage: "sparkles.tv", description: Text("点击“搜索”按钮开始匹配"))
                    }
                } else {
                    List {
                        ForEach(items) { item in
                            Button {
                                saveSelection(item)
                            } label: {
                                MatchRow(item: item)
                            }
                            .buttonStyle(.plain) // Keep row style clean
                            .listRowSeparator(.visible)
                        }

                        if hasMore && !items.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    loadNextPage()
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("手动匹配海报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                // Pre-fill logic using SeedPilotParser
                let metadata = SeedPilotParser.parse(taskName)
                searchText = metadata.title

                // Optional: Trigger search immediately?
                // User requirement: "点击搜索键才触发首次请求"
                // So we just fill the text.
            }
        }
    }

    // MARK: - Components

    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索电影或剧集...", text: $searchText)
                    .onSubmit {
                        performSearch()
                    }
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button("搜索") {
                performSearch()
            }
            .padding(.leading, 8)
            .disabled(searchText.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isLoading = true
        hasSearched = true
        currentPage = 1
        items = []
        hasMore = true

        Task {
            let results = await TMDBService.shared.search(query: searchText, page: 1)
            await MainActor.run {
                self.items = results
                self.isLoading = false
            }
        }
    }

    private func loadNextPage() {
        guard !isLoading && hasMore else { return }
        let nextPage = currentPage + 1

        Task {
            let results = await TMDBService.shared.search(query: searchText, page: nextPage)
            if results.isEmpty {
                hasMore = false
            } else {
                items.append(contentsOf: results)
                currentPage = nextPage
            }
        }
    }

    private func saveSelection(_ item: TMDBItem) {
        guard let path = item.posterPath else { return }
        TMDBService.shared.saveOverride(hash: taskHash, posterPath: path, context: modelContext)
        dismiss()
    }
}

// MARK: - Subviews

struct MatchRow: View {
    let item: TMDBItem

    var body: some View {
        HStack(spacing: 12) {
            // Left: Poster
            SimpleCachedImage(url: item.fullPosterURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: 45, height: 67.5)
                .cornerRadius(6)
                .clipped()

            // Right: Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.year)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(item.typeLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // Make full row tappable
    }
}
