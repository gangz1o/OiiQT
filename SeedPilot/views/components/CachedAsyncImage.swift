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

/// RSS source icon view with a unified fallback glyph.
/// If favicon URL is invalid or loading fails, shows RSS symbol instead of a blank placeholder.
struct RSSFaviconImage: View {
    let url: URL?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if loadFailed || url == nil {
                RSSFallbackIcon()
            } else {
                KFImage(url)
                    .placeholder { SeedPilotPlaceholder() }
                    .cacheOriginalImage()
                    .backgroundDecode()
                    .fade(duration: 0.2)
                    .cancelOnDisappear(true)
                    .onFailure { _ in
                        loadFailed = true
                    }
                    .resizable()
            }
        }
        .id(url?.absoluteString ?? "rss-fallback")
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

private struct RSSFallbackIcon: View {
    var body: some View {
        ZStack {
            SeedPilotPlaceholder()
            Image(systemName: "dot.radiowaves.up.forward")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}
