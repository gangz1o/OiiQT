//
//  RSSEmptyStateView.swift
//  SeedPilot
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
                Text("暂无订阅源")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text("添加您的第一个 RSS 订阅源，\n开启自动化下载之旅。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAddAction) {
                Text("添加订阅源")
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
