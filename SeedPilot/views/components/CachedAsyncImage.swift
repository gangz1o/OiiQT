//
//  CachedAsyncImage.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import Kingfisher

// MARK: - Unified Image Component

/// Drop-in replacement for AsyncImage, powered by Kingfisher.
/// Handles memory + disk caching, fade-in animation, and smooth gradient placeholders.
struct SimpleCachedImage: View {
    let url: URL?

    var body: some View {
        KFImage(url)
            .placeholder { SeedPilotPlaceholder() }
            .fade(duration: 0.25)
            .resizable()
    }
}

// MARK: - Gradient Placeholder

/// Smooth diagonal gradient placeholder — used across the entire app for loading & failure states.
struct SeedPilotPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemGray6), Color(.systemGray4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
