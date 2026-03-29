import Foundation
import SwiftUI

struct MediaDetailPageContentView: View {
    let viewState: MediaDetailPageViewState
    let onSearch: () -> Void
    let onPresentSearchFilters: () -> Void
    let onTapSearchResult: (String) -> Void

    var body: some View {
        ZStack {
            MediaDetailBackgroundView(url: viewState.hero.backgroundPosterURL)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    MediaDetailHeroSectionView(
                        viewState: viewState.hero,
                        onSearch: onSearch
                    )

                    MediaDetailSearchResultsSectionView(
                        viewState: viewState.search,
                        onPresentSearchFilters: onPresentSearchFilters,
                        onTapSearchResult: onTapSearchResult
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .safeAreaPadding(.bottom, 12)
        }
    }
}

private struct MediaDetailBackgroundView: View {
    let url: URL?

    var body: some View {
        GeometryReader { proxy in
            SimpleCachedImage(
                url: url,
                downsampleSize: CGSize(
                    width: max(proxy.size.width, 1),
                    height: max(proxy.size.height, 1)
                )
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .blur(radius: 48, opaque: true)
            .overlay(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}

private struct MediaDetailHeroSectionView: View {
    let viewState: MediaDetailHeroSectionViewState
    let onSearch: () -> Void

    private let posterSize = CGSize(width: 118, height: 176)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                MediaDetailPosterColumnView(
                    viewState: viewState,
                    posterSize: posterSize
                )

                MediaDetailHeroInfoColumnView(viewState: viewState)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            MediaDetailOverviewSectionView(
                text: viewState.overviewText,
                isLoading: viewState.isOverviewLoading,
                showsSyncProgress: viewState.showsSyncProgress
            )

            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private var actionButtons: some View {
        Button(action: onSearch) {
            Group {
                if viewState.isSearchLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(moviePilotLocalized("搜索"), systemImage: "magnifyingglass")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewState.isSearchLoading)
    }
}

private struct MediaDetailPosterColumnView: View {
    let viewState: MediaDetailHeroSectionViewState
    let posterSize: CGSize

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            SimpleCachedImage(
                url: viewState.posterURL,
                downsampleSize: posterSize
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: posterSize.width, height: posterSize.height)
            .background(SeedPilotPlaceholder())
            .compositingGroup()
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 10)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(moviePilotLocalized(viewState.mediaTypeText))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                    Text(viewState.ratingText.isEmpty ? moviePilotLocalized("暂无评分") : viewState.ratingText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewState.ratingText.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: posterSize.width, alignment: .center)
    }
}

private struct MediaDetailHeroInfoColumnView: View {
    let viewState: MediaDetailHeroSectionViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewState.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if viewState.isOverviewLoading {
                MediaDetailMetadataPlaceholderView()
            } else {
                MediaDetailMetadataRowGroupView(rows: viewState.metadataRows)
            }
        }
    }
}

private struct MediaDetailMetadataRowGroupView: View {
    let rows: [MediaDetailMetadataRowViewState]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    MediaDetailMetadataRowView(viewState: row)
                }
            }
        }
    }
}

private struct MediaDetailMetadataPlaceholderView: View {
    var rowCount: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<rowCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.secondary.opacity(0.16))
                        .frame(width: 46, height: 10)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.secondary.opacity(0.16))
                        .frame(maxWidth: index == rowCount - 1 ? 170 : .infinity)
                        .frame(height: 12)
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct MediaDetailMetadataRowView: View {
    let viewState: MediaDetailMetadataRowViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: viewState.systemImage)
                    .font(.caption2.weight(.semibold))
                Text(moviePilotLocalized(viewState.label))
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.tertiary)

            Text(moviePilotLocalized(viewState.value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(viewState.lineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MediaDetailOverviewSectionView: View {
    let text: String?
    let isLoading: Bool
    let showsSyncProgress: Bool
    var showsSectionHeader: Bool = true
    var collapsedLineLimit: Int = 5
    var textFont: Font = .callout
    var lineSpacing: CGFloat = 6
    var contentColor: Color = .primary.opacity(0.84)

    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: showsSectionHeader ? 10 : 8) {
            if showsSectionHeader {
                MediaDetailSectionHeader(title: moviePilotLocalized("简介"))
            }

            if isLoading {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.secondary.opacity(0.18))
                            .frame(maxWidth: index == 2 ? 200 : .infinity)
                            .frame(height: 13)
                    }
                }
                .redacted(reason: .placeholder)
            } else {
                let resolvedText = moviePilotLocalized(Self.resolvedOverviewText(text) ?? "暂无简介")

                Text(resolvedText)
                    .font(textFont)
                    .foregroundStyle(contentColor)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : collapsedLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        MediaDetailOverviewMeasurementView(
                            text: resolvedText,
                            collapsedLineLimit: collapsedLineLimit,
                            textFont: textFont,
                            lineSpacing: lineSpacing,
                            collapsedHeight: $collapsedHeight,
                            expandedHeight: $expandedHeight
                        )
                    }

                if canExpand {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(moviePilotLocalized(isExpanded ? "收起" : "展开"))
                            .font((showsSectionHeader ? Font.footnote : Font.caption).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsSyncProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(moviePilotLocalized("正在同步详情"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: text) {
            isExpanded = false
            collapsedHeight = 0
            expandedHeight = 0
        }
    }

    private var canExpand: Bool {
        expandedHeight > collapsedHeight + 1
    }

    private static func resolvedOverviewText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct MediaDetailOverviewMeasurementView: View {
    let text: String
    let collapsedLineLimit: Int
    let textFont: Font
    let lineSpacing: CGFloat
    @Binding var collapsedHeight: CGFloat
    @Binding var expandedHeight: CGFloat

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                measurementText(lineLimit: collapsedLineLimit)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newValue in
                        collapsedHeight = newValue
                    }
            }
            .overlay(alignment: .topLeading) {
                measurementText(lineLimit: nil)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newValue in
                        expandedHeight = newValue
                    }
            }
            .allowsHitTesting(false)
    }

    private func measurementText(lineLimit: Int?) -> some View {
        Text(text)
            .font(textFont)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MediaDetailSearchResultsSectionView: View {
    let viewState: MediaDetailSearchSectionViewState
    let onPresentSearchFilters: () -> Void
    let onTapSearchResult: (String) -> Void

    var body: some View {
        if viewState.content != .hidden {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MediaDetailSectionHeader(title: moviePilotLocalized("搜索结果"))

                    Spacer(minLength: 12)

                    if viewState.showsFilterButton {
                        Button(action: onPresentSearchFilters) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption.weight(.semibold))
                                Text(moviePilotLocalized("筛选与排序"))
                                    .font(.footnote.weight(.semibold))

                                if viewState.activeFilterCount > 0 {
                                    Text("\(viewState.activeFilterCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(.tint)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let feedbackText = viewState.feedbackText {
                    Text(moviePilotLocalized(feedbackText))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch viewState.content {
                case .hidden:
                    EmptyView()
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(moviePilotLocalized("正在检索站点资源"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                case .empty:
                    ContentUnavailableView(
                        moviePilotLocalized("还没有资源结果"),
                        systemImage: "magnifyingglass.circle",
                        description: Text(moviePilotLocalized(viewState.feedbackText ?? "点击下方搜索按钮后会显示结果。"))
                    )
                case .filteredEmpty:
                    ContentUnavailableView(
                        moviePilotLocalized("没有符合条件的资源"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(moviePilotLocalized("调整筛选条件后再试。"))
                    )
                case let .results(results):
                    SearchResultListView(
                        results: results,
                        onTapResult: onTapSearchResult
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MediaDetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(moviePilotLocalized(title))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

private struct SearchResultListView: View, Equatable {
    let results: [SearchResultViewState]
    let onTapResult: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                VStack(spacing: 0) {
                    SearchResultRowView(viewState: result)
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTapResult(result.id)
                        }
                        .contextMenu {
                            if let pageURL = result.pageURL {
                                Link(destination: pageURL) {
                                    Label(moviePilotLocalized("在浏览器中打开"), systemImage: "safari")
                                }
                            }
                        }
                    
                    if index < results.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    static func == (lhs: SearchResultListView, rhs: SearchResultListView) -> Bool {
        lhs.results == rhs.results
    }
}

private struct SearchResultRowView: View, Equatable {
    let viewState: SearchResultViewState

    static func == (lhs: SearchResultRowView, rhs: SearchResultRowView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewState.siteName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let promotionTag = viewState.promotionTag,
                   let promotionPalette = viewState.promotionPalette {
                    Text(promotionTag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(searchResultHex: promotionPalette.foregroundHex))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(searchResultHex: promotionPalette.backgroundHex))
                        )
                }

                Spacer(minLength: 6)

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text(viewState.seedersCount.formatted(.number.grouping(.automatic)))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.green.opacity(0.85))

                Text(viewState.sizeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(viewState.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !viewState.subtitle.isEmpty {
                Text(viewState.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !viewState.badges.isEmpty {
                SearchResultBadgeStripView(badges: viewState.badges)
                    .equatable()
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewState.accessibilityLabel)
    }
}

private struct SearchResultBadgeStripView: View, Equatable {
    let badges: [SearchResultBadgeViewState]

    static func == (lhs: SearchResultBadgeStripView, rhs: SearchResultBadgeStripView) -> Bool {
        lhs.badges == rhs.badges
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(badges) { badge in
                    Text(badge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(searchResultHex: badge.palette.foregroundHex))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(searchResultHex: badge.palette.backgroundHex))
                        )
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private extension Color {
    init(searchResultHex hex: String) {
        let sanitizedHex = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitizedHex).scanHexInt64(&value)

        let red, green, blue, alpha: Double
        switch sanitizedHex.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
