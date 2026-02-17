//
//  DashboardTile.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

enum DashboardGrid {
    static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
}

struct DashboardTile<Content: View>: View {
    let minHeight: CGFloat
    @ViewBuilder let content: () -> Content

    init(minHeight: CGFloat = 86, @ViewBuilder content: @escaping () -> Content) {
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}
