//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI
import SwiftData

struct TorrentRowView: View, Equatable {
    static func == (lhs: TorrentRowView, rhs: TorrentRowView) -> Bool {
        lhs.task.hash == rhs.task.hash &&
        lhs.task.status == rhs.task.status &&
        lhs.task.progress == rhs.task.progress &&
        lhs.task.downloadSpeed == rhs.task.downloadSpeed &&
        lhs.task.uploadSpeed == rhs.task.uploadSpeed &&
        lhs.task.seedingTime == rhs.task.seedingTime &&
        lhs.task.numSeeds == rhs.task.numSeeds &&
        lhs.task.numPeers == rhs.task.numPeers &&
        lhs.task.ratio == rhs.task.ratio &&
        lhs.task.category == rhs.task.category &&
        lhs.task.tags == rhs.task.tags &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isEditing == rhs.isEditing &&
        lhs.serverType == rhs.serverType &&
        lhs.posterURL == rhs.posterURL
    }

    let task: TorrentTask
    let isSelected: Bool
    let isEditing: Bool
    let toggleSelection: () -> Void
    let onShowActionSheet: (TorrentTask, URL?) -> Void

    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @AppStorage("isProUser") private var isProUser: Bool = false
    @AppStorage("hideDataNodeName") private var hideDataNodeName: Bool = false
    @Environment(\.modelContext) private var modelContext
    /// Pre-computed at call site. nil = single-server mode (no icon shown).
    let serverType: ServerType?

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
                        HStack(spacing: 6) {
                            // Tracker
                            if !hideDataNodeName {
                                Text(verbatim: displayedTracker)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .frame(minHeight: Self.headerInlinePillMinHeight)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }

                            if hasHeaderTaxonomyTags {
                                headerTaxonomyInlineView
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .clipped()
                            } else {
                                Spacer(minLength: 0)
                            }

                            // Status & Percent
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: task.status.localizedDisplayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(verbatim: task.displayText.percent)
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(statusColor)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }

                        // Title
                        // 插入零宽空格 (\u{200B}) 允许 SwiftUI 在点号后自由换行，防止中文字符和超长英文字符串被错误地绑定成一个不可分割的单词
                        let titleText = Text(verbatim: task.displayText.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        if let serverType {
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
                            downloadSpeedText: task.displayText.downloadSpeed,
                            uploadSpeedText: task.displayText.uploadSpeed,
                            peersText: task.displayText.peers,
                            seedsText: task.displayText.seeds,
                            sizeText: task.displayText.size,
                            ratioText: task.displayText.ratio,
                            seedingTimeText: compactSeedingTimeText,
                            savePathText: task.savePath.isEmpty ? "--" : task.savePath
                        )
                        .equatable()
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.trailing, 8)
                .padding(.leading, 14)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground)) // Card background
            .overlay(alignment: .leading) {
                VerticalEdgeProgressBar(
                    progress: task.progress,
                    status: task.status
                )
            }
            .clipShape(cardShape)
            .background {
                cardShape
                    .fill(Color.clear)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
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
        .task(id: "\(task.name)-\(LanguageManager.shared.selectedLanguage.rawValue)") {
            guard showTMDBData, posterURL == nil else { return }
            isLoadingPoster = true
            let url = await TMDBService.shared.fetchPoster(hash: task.hash, name: task.name, context: modelContext)
            if !Task.isCancelled {
                self.posterURL = url
                self.isLoadingPoster = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmdbPosterDidChange)) { notification in
            guard let changedHash = notification.userInfo?["hash"] as? String else { return }
            guard changedHash == task.hash else { return }
            // Force re-fetch: poster was manually changed
            self.posterURL = nil
            Task {
                isLoadingPoster = true
                let url = await TMDBService.shared.fetchPoster(hash: task.hash, name: task.name, context: modelContext)
                if !Task.isCancelled {
                    self.posterURL = url
                    self.isLoadingPoster = false
                }
            }
        }
    }


    // MARK: - Components

    private var posterArea: some View {
        Group {
            if let url = posterURL {
                SimpleCachedImage(
                    url: url,
                    downsampleSize: posterDownsampleSize,
                    cacheOriginal: false
                )
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var speedCapsule: some View {
        HStack(spacing: 4) {
            if task.status == .downloading {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(verbatim: formatBytes(task.downloadSpeed) + "/s")
            } else if task.status == .seeding {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(verbatim: formatBytes(task.uploadSpeed) + "/s")
            } else {
                Text(verbatim: task.status.localizedDisplayName)
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
        case .queued: return .indigo
        case .seeding: return .green
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
        }
    }

    private var displayCategory: String? {
        guard let serverType, serverType != .transmission else { return nil }
        let trimmed = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Lightweight merge: category (if any) + pre-computed tags, capped at 2.
    /// No string splitting, no Set, no sort, no `folding()` — all done at parse time.
    private var displayedHeaderTaxonomyTags: [String] {
        var result: [String] = []
        if let category = displayCategory {
            result.append(category)
        }
        let remaining = 2 - result.count
        if remaining > 0 {
            let tags = task.normalizedTags
            let slice = tags.prefix(remaining)
            result.append(contentsOf: slice)
        }
        return result
    }

    private var hiddenHeaderTaxonomyCount: Int {
        let totalCategory = (displayCategory != nil) ? 1 : 0
        let totalTags = task.normalizedTags.count
        return max(0, totalCategory + totalTags - 2)
    }

    private var hasHeaderTaxonomyTags: Bool {
        displayCategory != nil || !task.normalizedTags.isEmpty
    }

    private var headerTaxonomyInlineView: some View {
        HStack(spacing: 4) {
            ForEach(displayedHeaderTaxonomyTags, id: \.self) { tag in
                ColoredTagPill(
                    text: tag,
                    font: .system(size: 10, weight: .bold),
                    horizontalPadding: 6,
                    verticalPadding: 2,
                    minHeight: Self.headerInlinePillMinHeight
                )
            }

            if hiddenHeaderTaxonomyCount > 0 {
                Text(verbatim: "+\(hiddenHeaderTaxonomyCount)")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(minHeight: Self.headerInlinePillMinHeight)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .layoutPriority(0)
    }

    private var posterDownsampleSize: CGSize {
        CGSize(width: 65, height: 97.5)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var compactSeedingTimeText: String {
        TorrentRowView.compactDurationFormatter.string(from: max(0, task.seedingTime)) ?? task.displayText.seedingTime
    }
}

private extension TorrentRowView {
    static let headerInlinePillMinHeight: CGFloat = 20

    static let compactDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = [.dropLeading, .dropMiddle, .dropTrailing]
        return formatter
    }()

    var displayedTracker: String {
        guard isProUser else { return task.trackerHost }
        return TrackerAliasManager.shared.getAlias(for: task.trackerHost)
    }
}

struct VerticalEdgeProgressBar: View {
    let progress: Double
    let status: TorrentStatus

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .systemGray5))

            Rectangle()
                .fill(progressColor)
                .scaleEffect(y: clampedProgress, anchor: .bottom)
        }
        .frame(width: 4)
        .allowsHitTesting(false)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var progressColor: Color {
        switch status {
        case .downloading: return .blue
        case .queued: return .indigo
        case .seeding: return .green
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
        }
    }
}

struct GridRowIconText: View, Equatable {
    let icon: String
    let text: String
    var middleTruncation: Bool = false
    var expands: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(verbatim: text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(middleTruncation ? .middle : .tail)
                .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
        }
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    }
}

struct TaskProgressView: View, Equatable {
    let downloadSpeedText: String
    let uploadSpeedText: String
    let peersText: String
    let seedsText: String
    let sizeText: String
    let ratioText: String
    let seedingTimeText: String
    let savePathText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    GridRowIconText(icon: "arrow.down.circle", text: downloadSpeedText, expands: false).equatable()
                    GridRowIconText(icon: "arrow.down", text: peersText, expands: false).equatable()
                    GridRowIconText(icon: "doc", text: sizeText, expands: false).equatable()
                }

                GridRow {
                    GridRowIconText(icon: "arrow.up.circle", text: uploadSpeedText, expands: false).equatable()
                    GridRowIconText(icon: "leaf", text: seedsText, expands: false).equatable()
                    GridRowIconText(icon: "arrow.left.and.right", text: ratioText, expands: false).equatable()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 224, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                GridRowIconText(icon: "clock", text: seedingTimeText).equatable()
                GridRowIconText(icon: "folder", text: savePathText, middleTruncation: true).equatable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .font(.system(size: 10))
        .monospacedDigit()
    }
}
