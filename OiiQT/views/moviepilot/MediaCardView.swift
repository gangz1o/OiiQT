import SwiftUI
import NukeUI

struct MediaCardLayout: Equatable {
    static let strip = MediaCardLayout(width: 100)

    let width: CGFloat
    let posterAspectRatio: CGFloat

    init(width: CGFloat, posterAspectRatio: CGFloat = 2 / 3) {
        self.width = width
        self.posterAspectRatio = posterAspectRatio
    }

    var height: CGFloat {
        width / posterAspectRatio
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct MediaCardView: View {
    let viewState: MediaCardViewState
    let layout: MediaCardLayout

    init(viewState: MediaCardViewState, layout: MediaCardLayout = .strip) {
        self.viewState = viewState
        self.layout = layout
    }

    var body: some View {
        MediaCardContentView(viewState: viewState, layout: layout)
            .equatable()
    }
}

private struct MediaCardContentView: View, Equatable {
    static let ratingBadgeTint = Color(red: 0.43, green: 0.28, blue: 0.86)

    let viewState: MediaCardViewState
    let layout: MediaCardLayout

    static func == (lhs: MediaCardContentView, rhs: MediaCardContentView) -> Bool {
        lhs.viewState == rhs.viewState && lhs.layout == rhs.layout
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            posterImage

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.18), Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )

            titleOverlay
        }
        .frame(width: layout.width, height: layout.height)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 14))
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .overlay(alignment: .topLeading) {
            MediaCardBadge(text: moviePilotLocalized("剧集"), tint: .blue)
                .padding(8)
                .opacity(viewState.isSeries ? 1 : 0)
                .accessibilityHidden(!viewState.isSeries)
        }
        .overlay(alignment: .topTrailing) {
            if !viewState.ratingText.isEmpty {
                MediaCardBadge(text: viewState.ratingText, tint: Self.ratingBadgeTint)
                    .padding(8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var posterImage: some View {
        let request = viewState.posterURL.map {
            OiiQTImageLoading.request(for: $0, targetSize: layout.size)
        }

        return LazyImage(request: request, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { state in
            if let image = state.image {
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                MediaCardPlaceholderView()
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipped()
    }

    private var titleOverlay: some View {
        Text(viewState.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }

    private var accessibilityLabel: String {
        viewState.accessibilityLabel
    }
}

private struct MediaCardBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
    }
}

private struct MediaCardPlaceholderView: View {
    var body: some View {
        ZStack {
            OiiQTPlaceholder()

            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 52, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 10)
            }
            .padding(10)
        }
        .redacted(reason: .placeholder)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        MediaCardView(
            viewState: MediaCardViewState(
                id: "preview-card",
                posterURLString: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg",
                title: "Interstellar",
                ratingText: "8.7",
                isSeries: false
            )
        )
    }
}
