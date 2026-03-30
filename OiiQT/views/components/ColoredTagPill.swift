import SwiftUI

enum TagColorManager {
    private static let palette: [Color] = [
        .teal,
        .indigo,
        .pink,
        .orange,
        .purple,
        .cyan,
        .mint
    ]

    static func color(for tag: String) -> Color {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .secondary }

        // Stable hash to keep the same tag color across launches.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in normalized.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }

        return palette[Int(hash % UInt64(palette.count))]
    }
}

private struct AdaptiveTagCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let color: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minHeight: CGFloat?

    private var foregroundColor: Color {
        colorScheme == .dark ? color.opacity(0.92) : color
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? color.opacity(0.22) : color.opacity(0.15)
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minHeight)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}

extension View {
    func adaptiveTagCapsule(
        color: Color,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        minHeight: CGFloat? = nil
    ) -> some View {
        modifier(
            AdaptiveTagCapsuleModifier(
                color: color,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                minHeight: minHeight
            )
        )
    }
}

struct ColoredTagPill: View {
    let text: String
    var font: Font = .caption2.weight(.semibold)
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4
    var minHeight: CGFloat? = nil
    var color: Color? = nil

    var body: some View {
        let tint = color ?? TagColorManager.color(for: text)

        Text(verbatim: text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .adaptiveTagCapsule(
                color: tint,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                minHeight: minHeight
            )
    }
}
