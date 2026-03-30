//
//  RSSView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

enum AutomationViewMode: String, CaseIterable, Identifiable {
    case sources
    case allItems

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .sources:
            return LanguageManager.shared.localized("Sources")
        case .allItems:
            return LanguageManager.shared.localized("All Items")
        }
    }
}

struct RSSView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMode: AutomationViewMode = .sources
    @AppStorage("rss_layout_is_grid") private var isGridView: Bool = true
    // Query Sources from SwiftData
    @Query(sort: \RSSFeedSource.lastUpdated, order: .reverse) private var sources: [RSSFeedSource]

    @State private var showingAddSheet = false
    @State private var editingSource: RSSFeedSource? // For Edit Rule Sheet
    @State private var refreshingSourceId: UUID? // Track which source is refreshing

    // Grid Setup
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Picker
                Picker(LanguageManager.shared.localized("View Mode"), selection: $selectedMode) {
                    ForEach(AutomationViewMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(.systemGroupedBackground)) // Blend with body background

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if selectedMode == .sources {
                        if sources.isEmpty {
                            RSSEmptyStateView {
                                showingAddSheet = true
                            }
                        } else {
                            ScrollView {
                                if isGridView {
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(sources) { source in
                                            // Use NavigationLink to go to Detail View
                                            NavigationLink(destination: RSSFeedDetailView(source: source)) {
                                                RSSFeedTileView(
                                                    source: source,
                                                    isRefreshing: refreshingSourceId == source.id,
                                                    onRefresh: {
                                                        refreshSource(source)
                                                    },
                                                    onEditRules: {
                                                        editingSource = source
                                                    },
                                                    onDelete: {
                                                        withAnimation {
                                                            modelContext.delete(source)
                                                        }
                                                        RSSFeedSourceCloudSyncManager.shared.start(with: modelContext)
                                                        RSSFeedSourceCloudSyncManager.shared.handleLocalSourceConfigsChanged()
                                                    }
                                                )
                                                .frame(height: 180) // Fixed height for uniformity
                                            }
                                            .buttonStyle(PlainButtonStyle()) // Needed for Tile interactions/Context Menu to work properly inside Link
                                        }
                                    }
                                    .padding()
                                } else {
                                    LazyVStack(spacing: 12) {
                                        ForEach(sources) { source in
                                            NavigationLink(destination: RSSFeedDetailView(source: source)) {
                                                RSSFeedListRowView(
                                                    source: source,
                                                    isRefreshing: refreshingSourceId == source.id,
                                                    onRefresh: {
                                                        refreshSource(source)
                                                    },
                                                    onEditRules: {
                                                        editingSource = source
                                                    },
                                                    onDelete: {
                                                        withAnimation {
                                                            modelContext.delete(source)
                                                        }
                                                        RSSFeedSourceCloudSyncManager.shared.start(with: modelContext)
                                                        RSSFeedSourceCloudSyncManager.shared.handleLocalSourceConfigsChanged()
                                                    }
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            }
                            .defersAppRefreshWhileScrolling("rss.sources")
                        }
                    } else {
                        AllActivityView()
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Automation"))
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedMode == .sources {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isGridView.toggle()
                            }
                        } label: {
                            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .accessibilityLabel(
                            isGridView
                                ? LanguageManager.shared.localized("Switch to List Layout")
                                : LanguageManager.shared.localized("Switch to Grid Layout")
                        )
                    }

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRSSSourceSheet()
                    .presentationDetents([.medium])
            }
            .sheet(item: $editingSource) { source in
                EditRSSRuleView(source: source)
            }
        }
    }

    // MARK: - Actions

    private func refreshSource(_ source: RSSFeedSource) {
        guard refreshingSourceId == nil else { return }
        refreshingSourceId = source.id

        Task {
            await RSSMonitor.shared.refreshSource(source, context: modelContext)
            await MainActor.run {
                withAnimation {
                    refreshingSourceId = nil
                }
            }
        }
    }
}

#Preview {
    RSSView()
        .modelContainer(for: [RSSFeedSource.self, RSSItem.self], inMemory: true)
}
