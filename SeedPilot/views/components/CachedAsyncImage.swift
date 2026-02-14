//
//  CachedAsyncImage.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let cacheKey: String? // Usually the last path component (e.g. filename)
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let uiImage = image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: url) { _, _ in
            loadImage() // Reload if URL changes
        }
    }

    private func loadImage() {
        guard let url = url else { return }

        // Key generation logic: use provided key or MD5 of URL?
        // Simple usage: use url.lastPathComponent if unique enough (TMDB posters are unique IDs).
        // Or hash of absolute string.
        let key = cacheKey ?? url.lastPathComponent

        isLoading = true

        Task {
            // Check cache
            if let cached = ImageCacheManager.shared.image(forKey: key) {
                await MainActor.run {
                    self.image = cached
                    self.isLoading = false
                }
                return
            }

            // Download
            let downloaded = await ImageCacheManager.shared.downloadImage(url: url, key: key)
            await MainActor.run {
                self.image = downloaded
                self.isLoading = false
            }
        }
    }
}
