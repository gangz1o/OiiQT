//
//  QuickFilterBar.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

enum TaskStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case active
    case downloading
    case seeding
    case paused
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return LanguageManager.shared.localized("All")
        case .active:
            return LanguageManager.shared.localized("Active")
        case .downloading:
            return LanguageManager.shared.localized("Downloading")
        case .seeding:
            return LanguageManager.shared.localized("Seeding")
        case .paused:
            return LanguageManager.shared.localized("Paused")
        case .error:
            return LanguageManager.shared.localized("Error")
        }
    }

    var color: Color {
        switch self {
        case .active: return .mint
        case .downloading: return .blue
        case .seeding: return .green
        case .paused: return .gray
        case .error: return .red
        case .all: return .blue
        }
    }

    func matches(_ status: TorrentStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return status == .downloading || status == .seeding
        case .downloading:
            return status == .downloading
        case .seeding:
            return status == .seeding
        case .paused:
            return status == .paused || status == .queued
        case .error:
            return status == .error
        }
    }

    func matches(_ task: TorrentTask) -> Bool {
        switch self {
        case .active:
            return task.downloadSpeed > 0 || task.uploadSpeed > 0
        default:
            return matches(task.status)
        }
    }
}

struct QuickFilterBar: View {
    @Binding var selectedStatus: TaskStatusFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskStatusFilter.allCases) { status in
                    FilterCapsule(
                        text: status.title,
                        isSelected: selectedStatus == status,
                        color: status.color
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
