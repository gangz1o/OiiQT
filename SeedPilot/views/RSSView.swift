//
//  RSSView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

enum AutomationViewMode: String, CaseIterable, Identifiable {
    case sources = "订阅源"
    case allItems = "全量动态"

    var id: String { rawValue }
}

struct RSSView: View {
    @State private var selectedMode: AutomationViewMode = .sources
    @State private var sources: [RSSFeedSource] = RSSFeedSource.examples
    @State private var showingAddSheet = false

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
                                                    // Mock refresh or trigger manager
                                                },
                                                onEditRules: {
                                                    // Mock edit
                                                },
                                                onDelete: {
                                                    if let index = sources.firstIndex(where: { $0.id == source.id }) {
                                                        _ = withAnimation {
                                                            sources.remove(at: index)
                                                        }
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
                AddRSSSourceSheet(sources: $sources)
                    .presentationDetents([.medium])
            }
        }
    }
}

#Preview {
    RSSView()
}
