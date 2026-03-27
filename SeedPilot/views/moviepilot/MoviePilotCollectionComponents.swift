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
    @Namespace private var heroTransition
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
                .matchedTransitionSource(id: item.id, in: heroTransition)
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
    static let posterWidth: CGFloat = 72
    static let posterHeight: CGFloat = 108
    static let posterSize = CGSize(width: posterWidth, height: posterHeight)

    let viewState: MediaCardViewState

    static func == (lhs: MoviePilotSectionListRowContentView, rhs: MoviePilotSectionListRowContentView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SimpleCachedImage(
                url: viewState.posterURL,
                downsampleSize: Self.posterSize,
                cacheOriginal: false
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.posterWidth, height: Self.posterHeight)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(viewState.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if !viewState.ratingText.isEmpty {
                        Label(viewState.ratingText, systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                    }

                    Text(viewState.mediaTypeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text("查看详情")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 18))
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

            Text(isLoading ? "正在加载更多" : "加载更多")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
