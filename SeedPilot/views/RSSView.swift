//
//  RSSView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

enum AutomationViewMode: String, CaseIterable, Identifiable {
    case sources = "订阅源"
    case allItems = "全量动态"

    var id: String { rawValue }
}

struct RSSView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMode: AutomationViewMode = .sources
    // Query Sources from SwiftData
    @Query(sort: \RSSFeedSource.lastUpdated, order: .reverse) private var sources: [RSSFeedSource]

    @State private var showingAddSheet = false
    @State private var editingSource: RSSFeedSource? // For Edit Rule Sheet

    // Grid Setup
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Picker
                Picker("视图模式", selection: $selectedMode) {
                    ForEach(AutomationViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
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
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(sources) { source in
                                        // Use NavigationLink to go to Detail View
                                        NavigationLink(destination: RSSFeedDetailView(source: source)) {
                                            RSSFeedTileView(
                                                source: source,
                                                onRefresh: {
                                                    // Refresh logic to be implemented (likely fetch and update context)
                                                },
                                                onEditRules: {
                                                    editingSource = source
                                                },
                                                onDelete: {
                                                    withAnimation {
                                                        modelContext.delete(source)
                                                    }
                                                }
                                            )
                                            .frame(height: 180) // Fixed height for uniformity
                                        }
                                        .buttonStyle(PlainButtonStyle()) // Needed for Tile interactions/Context Menu to work properly inside Link
                                    }
                                }
                                .padding()
                            }
                        }
                    } else {
                        // Placeholder for "All Items"
                        ContentUnavailableView(
                            "全量动态",
                            systemImage: "list.bullet.rectangle.portrait",
                            description: Text("查看所有订阅源的最新更新聚合。")
                        )
                    }
                }
            }
            .navigationTitle("自动化")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 22))
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
}

#Preview {
    RSSView()
        .modelContainer(for: [RSSFeedSource.self, RSSItem.self], inMemory: true)
}
