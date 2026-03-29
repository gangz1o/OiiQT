import SwiftUI

extension View {
    func moviePilotListRowInsets(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct MoviePilotSectionPosterGridView: View, Equatable {
    private static let idealPosterWidth: CGFloat = 118
    private static let minimumColumnCount = 2
    private static let maximumColumnCount = 6
    private static let gridSpacing: CGFloat = 12

    @State private var availableWidth: CGFloat = 0
    let items: [MediaCardViewState]

    static func == (lhs: MoviePilotSectionPosterGridView, rhs: MoviePilotSectionPosterGridView) -> Bool {
        lhs.items == rhs.items
    }

    var body: some View {
        let metrics = Self.metrics(for: availableWidth)

        LazyVGrid(columns: metrics.columns, alignment: .center, spacing: Self.gridSpacing) {
            ForEach(items) { item in
                NavigationLink(value: MoviePilotSectionListMediaDestination(mediaID: item.id)) {
                    MediaCardView(viewState: item, layout: metrics.layout)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    floor(proxy.size.width)
                } action: { newWidth in
                    guard newWidth > 0, newWidth != availableWidth else { return }
                    availableWidth = newWidth
                }
        }
    }

    private static func metrics(for availableWidth: CGFloat) -> GridMetrics {
        let fallbackWidth = MediaCardLayout.strip.width * CGFloat(minimumColumnCount)
            + gridSpacing * CGFloat(minimumColumnCount - 1)
        let width = max(availableWidth, fallbackWidth)
        let rawColumnCount = Int((width + gridSpacing) / (idealPosterWidth + gridSpacing))
        let columnCount = min(max(rawColumnCount, minimumColumnCount), maximumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((width - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return GridMetrics(columns: columns, layout: MediaCardLayout(width: posterWidth))
    }

    private struct GridMetrics {
        let columns: [GridItem]
        let layout: MediaCardLayout
    }
}

struct MoviePilotSectionListRowView: View {
    let viewState: MediaCardViewState

    var body: some View {
        MoviePilotSectionListRowContentView(viewState: viewState)
            .equatable()
    }
}

struct MoviePilotSectionListRowContentView: View, Equatable {
    static let posterWidth: CGFloat = 80
    static let posterHeight: CGFloat = 120
    static let posterSize = CGSize(width: posterWidth, height: posterHeight)

    let viewState: MediaCardViewState

    static func == (lhs: MoviePilotSectionListRowContentView, rhs: MoviePilotSectionListRowContentView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                SimpleCachedImage(
                    url: viewState.posterURL,
                    downsampleSize: Self.posterSize,
                    cacheOriginal: false
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.posterWidth, height: Self.posterHeight)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(viewState.title)
                            .font(.system(.body, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !viewState.year.isEmpty {
                            Text(viewState.year)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        if !viewState.ratingText.isEmpty {
                            Label(viewState.ratingText, systemImage: "star.fill")
                                .font(.system(.caption, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }

                        Text(moviePilotLocalized(viewState.mediaTypeText))
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }

                    if !viewState.castNames.isEmpty {
                        Text(viewState.castNames.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if !viewState.overview.isEmpty {
                        Text(viewState.overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .truncationMode(.tail)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)

            Divider()
                .padding(.leading, Self.posterWidth + 14)
                .padding(.trailing, -16)
        }
        .contentShape(Rectangle())
    }
}

struct MoviePilotSectionListLoadMoreView: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(moviePilotLocalized(isLoading ? "正在加载更多" : "加载更多"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
