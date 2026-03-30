//
//  RuleMatchPreviewView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import SwiftData

struct RuleMatchPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let source: RSSFeedSource

    @State private var items: [RSSItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isLoading && items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else if let error = errorMessage, items.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowBackground(Color.clear)
                    } else if items.isEmpty {
                        Text("No RSS items")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(items) { item in
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
                await loadItems()
            }
        }
    }

    @MainActor
    private func loadItems() async {
        isLoading = true
        errorMessage = nil

        let cachedItems = source.items.sorted { $0.pubDate > $1.pubDate }

        do {
            let fetched = try await RSSManager.shared.fetchRSS(source: source)
            let sortedFetched = fetched.sorted { $0.pubDate > $1.pubDate }
            self.items = sortedFetched.isEmpty ? cachedItems : sortedFetched
        } catch {
            self.items = cachedItems
            if cachedItems.isEmpty {
                self.errorMessage = error.localizedDescription
            }
        }

        isLoading = false
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
