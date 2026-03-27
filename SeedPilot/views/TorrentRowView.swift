//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI
import SwiftData

struct TorrentRowView: View, Equatable {
    let row: TransfersRowDisplayModel
    let showPoster: Bool
    let isSelected: Bool
    let isEditing: Bool
    let toggleSelection: () -> Void
    let onShowActionSheet: () -> Void

    static func == (lhs: TorrentRowView, rhs: TorrentRowView) -> Bool {
        lhs.row == rhs.row &&
        lhs.showPoster == rhs.showPoster &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isEditing == rhs.isEditing
    }

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                Button {
                    toggleSelection()
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                        .contentShape(Rectangle())
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .padding(.leading, 8)
            }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if showPoster {
                        posterArea
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            if let trackerText = row.trackerText {
                                Text(verbatim: trackerText)
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

                            if !row.taxonomyTags.isEmpty {
                                headerTaxonomyInlineView
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .clipped()
                            } else {
                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: row.status.localizedDisplayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(verbatim: row.percentText)
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(statusColor)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                        }

                        let titleText = Text(verbatim: row.titleText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        if let serverType = row.serverType {
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
                            downloadSpeedText: row.downloadSpeedText,
                            uploadSpeedText: row.uploadSpeedText,
                            peersText: row.peersText,
                            seedsText: row.seedsText,
                            sizeText: row.sizeText,
                            ratioText: row.ratioText,
                            seedingTimeText: row.seedingTimeText,
                            savePathText: row.savePathText
                        )
                        .equatable()
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.trailing, 8)
                .padding(.leading, 14)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(alignment: .leading) {
                VerticalEdgeProgressBar(
                    progress: row.progress,
                    status: row.status
                )
            }
            .clipShape(cardShape)
            .background {
                cardShape
                    .fill(Color.clear)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
        }
        .contentShape(Rectangle())
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
                onShowActionSheet()
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        )
    }

    private var posterArea: some View {
        TransfersPosterThumbnailView(
            taskHash: row.taskHash,
            taskRawName: row.taskRawName,
            isEnabled: showPoster,
            resolutionBadge: row.resolutionBadge,
            downsampleSize: posterDownsampleSize
        )
    }

    private var statusColor: Color {
        row.status.color
    }

    private var headerTaxonomyInlineView: some View {
        HStack(spacing: 4) {
            ForEach(row.taxonomyTags, id: \.self) { tag in
                ColoredTagPill(
                    text: tag,
                    font: .system(size: 10, weight: .bold),
                    horizontalPadding: 6,
                    verticalPadding: 2,
                    minHeight: Self.headerInlinePillMinHeight
                )
            }

            if row.hiddenTaxonomyCount > 0 {
                Text(verbatim: "+\(row.hiddenTaxonomyCount)")
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
}

private extension TorrentRowView {
    static let headerInlinePillMinHeight: CGFloat = 20
}

/// Self-contained poster thumbnail — resolves its own poster via @State + .task.
/// Zero coupling to ViewModel or filteredRows. SwiftUI only re-renders THIS view
/// when the poster URL resolves, not the entire 100K-element list.
private struct TransfersPosterThumbnailView: View {
    let taskHash: String
    let taskRawName: String
    let isEnabled: Bool
    let resolutionBadge: ResolutionBadge?
    let downsampleSize: CGSize

    @State private var posterURL: URL?
    @State private var hasResolved: Bool = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let posterURL {
                SimpleCachedImage(
                    url: posterURL,
                    downsampleSize: downsampleSize,
                    cacheOriginal: false,
                    enableFade: false
                )
                .aspectRatio(contentMode: .fill)
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
            if let resolutionBadge {
                DiagonalRibbonView(text: resolutionBadge.text, color: resolutionBadge.color)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: taskHash) {
            guard isEnabled, !hasResolved else { return }

            // Fast path: thread-safe NSCache lookup (no MainActor hop)
            if let cached = TMDBService.shared.cachedPosterURL(for: taskHash) {
                hasResolved = true
                posterURL = cached
                return
            }

            // Yield to avoid flooding main thread when many thumbnails appear at once
            await Task.yield()
            guard !Task.isCancelled else { return }

            // Slow path: @MainActor fetchPoster (SwiftData + network)
            let url = await TMDBService.shared.fetchPoster(
                hash: taskHash,
                name: taskRawName,
                context: modelContext
            )
            guard !Task.isCancelled else { return }
            hasResolved = true
            posterURL = url
            if let url {
                SeedPilotImagePreheater.prefetch(
                    url,
                    downsampleSize: downsampleSize,
                    cacheOriginal: false
                )
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            if !newValue {
                posterURL = nil
                hasResolved = false
            } else if !hasResolved {
                // Will re-trigger .task on next appearance cycle
                hasResolved = false
            }
        }
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
        status.color
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
