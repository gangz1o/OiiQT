import SwiftUI

struct MediaSectionView: View {
    let viewState: MediaSectionViewState
    let onTapMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(viewState.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Button(action: onTapMore) {
                    HStack(spacing: 4) {
                        Text("更多")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            MediaSectionCardsStripView(viewState: viewState)
                .equatable()
        }
    }
}

private struct MediaSectionCardsStripView: View, Equatable {
    let viewState: MediaSectionViewState

    @Namespace private var heroTransition

    static func == (lhs: MediaSectionCardsStripView, rhs: MediaSectionCardsStripView) -> Bool {
        lhs.viewState == rhs.viewState
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(viewState.cards) { card in
                    NavigationLink(value: card.id) {
                        MediaCardView(viewState: card)
                    }
                    .matchedTransitionSource(id: card.id, in: heroTransition)
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled() // 允许卡片阴影超出 ScrollView 边界显示
    }
}

#Preview {
    MediaSectionView(
        viewState: MediaSectionViewState(
            id: "preview-section",
            title: "TMDB 流行趋势",
            cards: [
                MediaCardViewState(
                    id: "preview-card-1",
                    posterURLString: "https://image.tmdb.org/t/p/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
                    title: "Interstellar",
                    ratingText: "8.7",
                    isSeries: false
                ),
                MediaCardViewState(
                    id: "preview-card-2",
                    posterURLString: "https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg",
                    title: "Breaking Bad",
                    ratingText: "9.5",
                    isSeries: true
                )
            ]
        ),
        onTapMore: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
