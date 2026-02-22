//
//  DiagonalRibbonView.swift
//  SeedPilot
//

import SwiftUI

struct DiagonalRibbonView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                color
                    .shadow(.inner(color: .black.opacity(0.2), radius: 1, x: 0, y: -1))
            )
            .clipShape(
                .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 0
                )
            )
            // Add a subtle border or glow to make it stand out against any poster
            .overlay(
                 RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            // No rotation, just a clean badge anchored top-left
    }
}

#Preview {
    Color.gray
        .frame(width: 100, height: 150)
        .overlay(alignment: .topLeading) {
            DiagonalRibbonView(text: "4K", color: .purple)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
}
