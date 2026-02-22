//
//  RSSFeedTileView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import Foundation

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
                SimpleCachedImage(url: URL(string: source.faviconUrl ?? ""))
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .systemBackground))
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
                    .minimumScaleFactor(0.8)

                Text(lastUpdatedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Badge (Brand Color Tag)
            if source.unreadCount > 0 {
                HStack {
                    Spacer()
                    Text(String(format: LanguageManager.shared.localized("%d unread"), source.unreadCount))
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contextMenu {
            Button(action: onRefresh) {
                Label(LanguageManager.shared.localized("Refresh Now"), systemImage: "arrow.clockwise")
            }
            Button(action: onEditRules) {
                Label(LanguageManager.shared.localized("Edit Rules"), systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive, action: onDelete) {
                Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
            }
        }
    }

    private var lastUpdatedDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: source.lastUpdated, relativeTo: Date())
        return String(format: LanguageManager.shared.localized("Updated %@"), relative)
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
