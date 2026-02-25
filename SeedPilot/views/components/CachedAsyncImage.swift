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
    var downsampleSize: CGSize? = nil

    var body: some View {
        if let downsampleSize {
            KFImage(url)
                .placeholder { SeedPilotPlaceholder() }
                .setProcessor(DownsamplingImageProcessor(size: downsampleSize))
                .backgroundDecode()
                .cacheOriginalImage()
                .fade(duration: 0.2)
                .cancelOnDisappear(true)
                .resizable()
        } else {
            KFImage(url)
                .placeholder { SeedPilotPlaceholder() }
                .cacheOriginalImage()
                .backgroundDecode()
                .fade(duration: 0.2)
                .cancelOnDisappear(true)
                .resizable()
        }
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
