//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI

struct TorrentRowView: View {
    let task: TorrentTask
    let isSelected: Bool
    let isEditing: Bool
    let toggleSelection: () -> Void
    let onShowActionSheet: (TorrentTask, URL?) -> Void

    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var trackerAliasManager = TrackerAliasManager.shared
    var appStateManager: AppStateManager

    @State private var posterURL: URL?
    @State private var isLoadingPoster = false

    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Checkbox (Edit Mode Only)
            if isEditing {
                Button {
                    toggleSelection()
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                        .contentShape(Rectangle()) // Make touch area larger
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .padding(.leading, 8)
            }

            // MARK: - Content
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // MARK: - 1. Left Poster Area
                    if showTMDBData {
                        posterArea
                    }

                    // MARK: - 2. Right Content Area
                    VStack(alignment: .leading, spacing: 8) {
                        // Feature 1: Top Status Bar
                        HStack {
                            // Tracker
                            Text(displayedTracker)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())

                            // Seeding Time / Added Date if not seeding
                            if task.status == .seeding {
                                 HStack(spacing: 2) {
                                    Image(systemName: "clock")
                                    Text(task.displayText.seedingTime)
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Status & Percent
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(task.status.localizedDisplayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(task.displayText.percent)
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(statusColor)
                            }
                        }

                        // Title
                        // 插入零宽空格 (\u{200B}) 允许 SwiftUI 在点号后自由换行，防止中文字符和超长英文字符串被错误地绑定成一个不可分割的单词
                        let titleText = Text(task.displayText.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        if appStateManager.activeServerId == nil,
                           let serverType = appStateManager.servers.first(where: { $0.id == task.serverID })?.type {
                            HStack(alignment: .center, spacing: 6) {
                                titleText
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Group {
                                    if serverType == .transmission {
                                        Image("tr_logo")
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Image("qb_logo")
                                            .resizable()
                                            .scaledToFit()
                                    }
                                }
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        } else {
                            titleText
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        TaskProgressView(
                            progress: task.progress,
                            status: task.status,
                            downloadSpeedText: task.displayText.downloadSpeed,
                            uploadSpeedText: task.displayText.uploadSpeed,
                            peersText: task.displayText.peers,
                            seedsText: task.displayText.seeds,
                            sizeText: task.displayText.size,
                            ratioText: task.displayText.ratio
                        )
                        .equatable()
                    }
                }
                .padding(8)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground)) // Card background
            .clipShape(cardShape)
            .background(
                cardShape
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
        .contentShape(Rectangle()) // Make the whole row tappable
        .gesture(
            isEditing ? TapGesture().onEnded {
                toggleSelection()
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } : nil
        )
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                guard !isEditing else { return }
                onShowActionSheet(task, posterURL)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        )
        .task(id: "\(task.name)-\(languageManager.selectedLanguage.rawValue)") {
            await refreshPosterAsync()
        }
    }

    private func refreshPosterAsync() async {
        guard showTMDBData else { return }
        isLoadingPoster = true
        let url = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext)
        if !Task.isCancelled {
            self.posterURL = url
            self.isLoadingPoster = false
        }
    }

    // MARK: - Components

    private var posterArea: some View {
        Group {
            if let url = posterURL {
                SimpleCachedImage(url: url, downsampleSize: posterDownsampleSize)
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingPoster {
                SeedPilotPlaceholder()
                    .overlay { ProgressView() }
            } else {
                SeedPilotPlaceholder()
                    .overlay {
                        Image(systemName: "sparkles.tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            }
        }
        .frame(width: 65, height: 97.5)
        .overlay(alignment: .topLeading) {
            if let badge = task.resolutionBadge {
                DiagonalRibbonView(text: badge.text, color: badge.color)
                    .drawingGroup()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var speedCapsule: some View {
        HStack(spacing: 4) {
            if task.status == .downloading {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(formatBytes(task.downloadSpeed) + "/s")
            } else if task.status == .seeding {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(formatBytes(task.uploadSpeed) + "/s")
            } else {
                Text(task.status.localizedDisplayName)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .seeding: return .green
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
        }
    }

    private var posterDownsampleSize: CGSize {
        CGSize(width: 65 * displayScale, height: 97.5 * displayScale)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

private extension TorrentRowView {
    var displayedTracker: String {
        trackerAliasManager.getAlias(for: task.trackerHost)
    }
}

// Helper View for Tags
struct TagCapsule: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
}

struct GridRowIconText: View, Equatable {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct TaskProgressView: View, Equatable {
    let progress: Double
    let status: TorrentStatus
    let downloadSpeedText: String
    let uploadSpeedText: String
    let peersText: String
    let seedsText: String
    let sizeText: String
    let ratioText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(progressColor)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)))
                        .animation(.smooth, value: progress)
                }
            }
            .frame(height: 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: 6) {
                GridRowIconText(icon: "arrow.down.circle", text: downloadSpeedText).equatable()
                GridRowIconText(icon: "arrow.down", text: peersText).equatable()
                GridRowIconText(icon: "doc", text: sizeText).equatable()

                GridRowIconText(icon: "arrow.up.circle", text: uploadSpeedText).equatable()
                GridRowIconText(icon: "leaf", text: seedsText).equatable()
                GridRowIconText(icon: "arrow.left.and.right", text: ratioText).equatable()
            }
        }
    }

    private var progressColor: Color {
        switch status {
        case .downloading: return .blue
        case .seeding: return .green
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
        }
    }
}
