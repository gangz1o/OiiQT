import Foundation
import SwiftUI

struct MediaDetailPageContentView: View {
    let viewState: MediaDetailPageViewState
    let onSearch: () -> Void
    let onSubscribe: () -> Void
    let onPresentSearchFilters: () -> Void
    let onTapSearchResult: (String) -> Void

    var body: some View {
        ZStack {
            MediaDetailBackgroundView(url: viewState.hero.backgroundPosterURL)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    MediaDetailHeroSectionView(
                        viewState: viewState.hero,
                        onSearch: onSearch,
                        onSubscribe: onSubscribe
                    )

                    MediaDetailActorsSectionView(viewState: viewState.actors)

                    MediaDetailSearchResultsSectionView(
                        viewState: viewState.search,
                        onPresentSearchFilters: onPresentSearchFilters,
                        onTapSearchResult: onTapSearchResult
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
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
    let onSubscribe: () -> Void

    private let bannerAspectRatio: CGFloat = 1.72

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
                .padding(.horizontal, -16)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.50), location: 0.0),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .padding(.horizontal, -16)
            .offset(y: -40)
            .padding(.bottom, -40)

            VStack(alignment: .leading, spacing: 10) {
                MediaDetailSectionHeader(title: "简介")
                    .padding(.top, 20)

                if viewState.isOverviewLoading {
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
                    Text(viewState.overviewText ?? "暂无简介")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewState.showsSyncProgress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在同步详情")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }

                HStack(spacing: 12) {
                    Button(action: onSearch) {
                        Group {
                            if viewState.isSearchLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.indigo)
                    .disabled(viewState.isSearchLoading)

                    Button(action: onSubscribe) {
                        Group {
                            if viewState.isSubscribeLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(
                                    viewState.isSubscribed ? "已订阅" : "订阅",
                                    systemImage: viewState.isSubscribed
                                        ? "checkmark.circle.fill"
                                        : "bell.fill"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(viewState.isSubscribed ? .teal : .green)
                    .disabled(viewState.isSubscribeLoading)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var banner: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                SimpleCachedImage(
                    url: viewState.bannerURL,
                    downsampleSize: CGSize(
                        width: max(proxy.size.width, 1),
                        height: max(proxy.size.height, 1)
                    )
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.55),
                        .init(color: .black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewState.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

                    HStack(spacing: 6) {
                        Text(viewState.mediaTypeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(.white.opacity(0.2)))

                        if !viewState.ratingText.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.yellow)
                                Text(viewState.ratingText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(.white.opacity(0.2)))
                        }

                        if viewState.isSubscribed {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("已订阅")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(.tint.opacity(0.75)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .aspectRatio(bannerAspectRatio, contentMode: .fit)
    }
}

private struct MediaDetailActorsSectionView: View {
    let viewState: MediaDetailActorsSectionViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaDetailSectionHeader(title: "演员表")

            if viewState.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { _ in
                            MediaActorPlaceholderCardView()
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            } else if viewState.actors.isEmpty {
                ContentUnavailableView(
                    "暂无演员信息",
                    systemImage: "person.2.slash",
                    description: Text("当前媒体没有返回可展示的演员表。")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(viewState.actors) { actor in
                            MediaActorCardView(viewState: actor)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediaActorPlaceholderCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Circle()
                .fill(.secondary.opacity(0.18))
                .frame(width: 72, height: 72)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.18))
                .frame(width: 72, height: 12)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.18))
                .frame(width: 54, height: 10)
        }
        .frame(width: 90, alignment: .leading)
        .redacted(reason: .placeholder)
    }
}

private struct MediaActorCardView: View {
    let viewState: ActorViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SimpleCachedImage(
                url: viewState.profileURL,
                downsampleSize: CGSize(width: 144, height: 144)
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 72, height: 72)
            .background(SeedPilotPlaceholder())
            .clipShape(Circle())

            Text(viewState.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(viewState.characterName.isEmpty ? "演员" : viewState.characterName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 90, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewState.accessibilityLabel)
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
                    MediaDetailSectionHeader(title: "搜索结果")

                    Spacer(minLength: 12)

                    if viewState.showsFilterButton {
                        Button(action: onPresentSearchFilters) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption.weight(.semibold))
                                Text("筛选与排序")
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
                    Text(feedbackText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch viewState.content {
                case .hidden:
                    EmptyView()
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在检索站点资源")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                case .empty:
                    ContentUnavailableView(
                        "还没有资源结果",
                        systemImage: "magnifyingglass.circle",
                        description: Text(viewState.feedbackText ?? "点击下方搜索按钮后会显示结果。")
                    )
                case .filteredEmpty:
                    ContentUnavailableView(
                        "没有符合条件的资源",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("调整筛选条件后再试。")
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
        Text(title)
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
        LazyVStack(spacing: 8) {
            ForEach(results) { result in
                SearchResultRowView(viewState: result)
                    .equatable()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapResult(result.id)
                    }
                    .contextMenu {
                        if let pageURL = result.pageURL {
                            Link(destination: pageURL) {
                                Label("在浏览器中打开", systemImage: "safari")
                            }
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
                .foregroundStyle(Color(red: 0.20, green: 0.64, blue: 0.31))

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
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
