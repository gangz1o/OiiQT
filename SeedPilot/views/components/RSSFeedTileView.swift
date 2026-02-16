//
//  RSSFeedTileView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

struct RSSFeedTileView: View {
    let source: RSSFeedSource
    var isRefreshing: Bool = false
    var onRefresh: () -> Void
    var onEditRules: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top: Favicon + refresh indicator
            HStack {
                AsyncImage(url: URL(string: source.faviconUrl ?? "")) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.1)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                Spacer()
                
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer()

            // Bottom Info
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(source.lastUpdated, style: .relative) 前更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Badge (Brand Color Tag)
            if source.unreadCount > 0 {
                HStack {
                    Spacer()
                    Text("\(source.unreadCount) 条未读")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contextMenu {
            Button(action: onRefresh) {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            Button(action: onEditRules) {
                Label("编辑规则", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
            RSSFeedTileView(
                source: RSSFeedSource.examples[0],
                onRefresh: {},
                onEditRules: {},
                onDelete: {}
            )
            RSSFeedTileView(
                source: RSSFeedSource.examples[1],
                onRefresh: {},
                onEditRules: {},
                onDelete: {}
            )
        }
        .padding()
    }
}
