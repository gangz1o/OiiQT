//
//  ManualMatchView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI
import SwiftData

struct ManualMatchView: View {
    let taskName: String
    let taskHash: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ManualPosterMatchViewModel

    init(taskName: String, taskHash: String) {
        self.taskName = taskName
        self.taskHash = taskHash
        _viewModel = State(initialValue: ManualPosterMatchViewModel(taskName: taskName, taskHash: taskHash))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar

                // Result List
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    if viewModel.hasSearched {
                        ContentUnavailableView(
                            LanguageManager.shared.localized("No Related Results Found"),
                            systemImage: "magnifyingglass",
                            description: Text(LanguageManager.shared.localized("Try different keywords or check spelling."))
                        )
                    } else {
                        ContentUnavailableView(
                            LanguageManager.shared.localized("Ready to Search"),
                            systemImage: "sparkles.tv",
                            description: Text(LanguageManager.shared.localized("Tap \"Search\" to start matching."))
                        )
                    }
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            Button {
                                saveSelection(item)
                            } label: {
                                MatchRow(item: item)
                            }
                            .buttonStyle(.plain) // Keep row style clean
                            .listRowSeparator(.visible)
                        }

                        if viewModel.hasMore && !viewModel.items.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    Task {
                                        await viewModel.loadNextPageIfNeeded()
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Manual Poster Matching"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Components

    @FocusState private var isSearchFocused: Bool

    private var searchBar: some View {
        HStack(spacing: 12) {
            // Inner Capsule
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField(LanguageManager.shared.localized("Search movies or series..."), text: $viewModel.searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await viewModel.performSearch()
                        }
                    }
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color(uiColor: .systemGray3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(uiColor: .systemGray6))
            .cornerRadius(10)

            // External Search Icon Button (iOS-style neutral look)
            Button {
                Task {
                    await viewModel.performSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(viewModel.searchText.isEmpty ? .tertiary : .secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LanguageManager.shared.localized("Search"))
            .disabled(viewModel.searchText.isEmpty)
            .opacity(viewModel.searchText.isEmpty ? 0.8 : 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onAppear {
            if !viewModel.searchText.isEmpty {
                isSearchFocused = true
            }
        }
    }

    private func saveSelection(_ item: PosterSearchCandidate) {
        guard item.posterURL != nil else { return }
        viewModel.saveSelection(item, context: modelContext)
        dismiss()
    }
}

// MARK: - Subviews

struct MatchRow: View {
    let item: PosterSearchCandidate

    var body: some View {
        HStack(spacing: 12) {
            // Left: Poster
            SimpleCachedImage(
                url: item.posterURL,
                downsampleSize: CGSize(width: 45, height: 67.5),
                cacheOriginal: false
            )
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
                    if !item.year.isEmpty {
                        Text(item.year)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.typeLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)

                    Text(item.sourceLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.source == .douban ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
                        .cornerRadius(4)
                }

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // Make full row tappable
    }
}
