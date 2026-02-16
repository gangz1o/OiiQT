//
//  CachedAsyncImage.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

/// A native replacement for Kingfisher's KFImage using standard AsyncImage with URLCache.
/// Provides consistent API for the rest of the app.
struct SimpleCachedImage: View {
    let url: URL?

    var body: some View {
        if let url = url {
            // Using AsyncImage relying on URLCache.shared which we configured in App.init
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.1)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            ZStack {
                Color.gray.opacity(0.1)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Keep the generic struct if we need it later, but simplified for now to strict match usage
struct CachedAsyncImage<Content: View, Placeholder: View>: View where Content: View, Placeholder: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(image)
            case .empty:
                placeholder()
            case .failure:
                // We could expose failure, but for now just show placeholder or empty
                placeholder()
            @unknown default:
                placeholder()
            }
        }
    }
}
