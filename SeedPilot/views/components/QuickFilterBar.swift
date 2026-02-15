//
//  QuickFilterBar.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct QuickFilterBar: View {
    @Binding var selectedStatus: String

    // Hardcoded options to match the requested filtering logic
    private let options = ["全部", "下载中", "做种中", "暂停", "错误"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { status in
                    FilterCapsule(
                        text: status,
                        isSelected: selectedStatus == status,
                        // Match colors from TorrentStatus where possible
                        color: color(for: status)
                    ) {
                        withAnimation(.spring()) {
                            selectedStatus = status
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func color(for status: String) -> Color {
        switch status {
        case "下载中": return .blue
        case "做种中": return .green
        case "暂停": return .gray
        case "错误": return .red
        default: return .blue // Default accent for "全部"
        }
    }
}

struct FilterCapsule: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5)
                )
                .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}
