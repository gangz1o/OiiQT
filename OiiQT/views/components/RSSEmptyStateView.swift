//
//  RSSEmptyStateView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

struct RSSEmptyStateView: View {
    var onAddAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

            VStack(spacing: 12) {
                Text(LanguageManager.shared.localized("No Sources Yet"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(LanguageManager.shared.localized("Add your first RSS source to start your automation workflow."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }

            Button(action: onAddAction) {
                Text(LanguageManager.shared.localized("Add Source"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: .accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    RSSEmptyStateView(onAddAction: {})
}
