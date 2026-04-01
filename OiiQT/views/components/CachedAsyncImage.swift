//
//  CachedAsyncImage.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import Nuke
import NukeUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Image Loading Infrastructure

enum OiiQTImageLoading {
    static let processingQueue = DispatchQueue.global(qos: .userInitiated)

    static var displayScale: CGFloat {
        #if os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2
        #else
        UIScreen.main.scale
        #endif
    }

    static func needsDoubanHeaders(for url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("doubanio.com")
    }

    /// Build a Nuke `ImageRequest` for the given URL.
    /// - If the URL is a Douban image, injects the required HTTP headers.
    /// - If `targetSize` is supplied, appends a `Resize` processor (in points, automatically scaled to pixels by Nuke).
    static func request(for url: URL, targetSize: CGSize? = nil) -> ImageRequest {
        var urlRequest = URLRequest(url: url)

        if needsDoubanHeaders(for: url) {
            urlRequest.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            urlRequest.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            urlRequest.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }

        var processors: [ImageProcessing] = []
        if let size = targetSize {
            // `.points` unit → Nuke multiplies by screen scale automatically, equivalent to
            // Kingfisher's scaleFactor(displayScale) + downsampling(size:).
            processors.append(ImageProcessors.Resize(size: size, unit: .points))
        }

        return ImageRequest(urlRequest: urlRequest, processors: processors)
    }
}

// MARK: - SSL Authentication (Simulator only)
// On real devices the system handles Douban SSL correctly without custom delegation.
// In the simulator, some certificate chains are not trusted by default, so we
// explicitly trust doubanio.com server certificates.
#if targetEnvironment(simulator)
final class OiiQTDoubanSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              !challenge.protectionSpace.host.isEmpty,
              let serverTrust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.host.lowercased().hasSuffix("doubanio.com") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
#endif

// MARK: - Image Preheater

/// Prefetches images into Nuke's cache, deduplicating concurrent requests for the same URL.
@MainActor
enum OiiQTImagePreheater {
    private static var activeTasks: [String: Task<Void, Never>] = [:]

    static func prefetch(_ url: URL?, targetSize: CGSize? = nil) {
        guard let url else { return }
        let key = cacheKey(for: url, targetSize: targetSize)
        guard activeTasks[key] == nil else { return }

        let request = OiiQTImageLoading.request(for: url, targetSize: targetSize)
        activeTasks[key] = Task {
            _ = try? await ImagePipeline.shared.image(for: request)
            activeTasks.removeValue(forKey: key)
        }
    }

    private static func cacheKey(for url: URL, targetSize: CGSize?) -> String {
        guard let size = targetSize else { return url.absoluteString }
        return "\(url.absoluteString)|w=\(Int(size.width.rounded()))|h=\(Int(size.height.rounded()))"
    }
}

// MARK: - Unified Image Component

/// Drop-in replacement for AsyncImage, powered by Nuke.
/// Handles memory + disk caching, fade-in animation, and smooth gradient placeholders.
struct SimpleCachedImage: View {
    let url: URL?
    var downsampleSize: CGSize? = nil
    /// Kept for API compatibility. Nuke always caches the raw compressed data on disk by default.
    var cacheOriginal: Bool = true
    var enableFade: Bool = true

    private var request: ImageRequest? {
        url.map { OiiQTImageLoading.request(for: $0, targetSize: downsampleSize) }
    }

    var body: some View {
        LazyImage(
            request: request,
            transaction: enableFade
                ? Transaction(animation: .easeInOut(duration: 0.2))
                : Transaction()
        ) { state in
            if let image = state.image {
                image.resizable()
            } else {
                OiiQTPlaceholder()
            }
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
                LazyImage(
                    request: url.map { OiiQTImageLoading.request(for: $0) },
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { state in
                    if let image = state.image {
                        image.resizable()
                    } else {
                        OiiQTPlaceholder()
                    }
                }
                .onCompletion { result in
                    if case .failure = result {
                        loadFailed = true
                    }
                }
            }
        }
        .id(url?.absoluteString ?? "rss-fallback")
    }
}

// MARK: - Gradient Placeholder

/// Smooth diagonal gradient placeholder — used across the entire app for loading & failure states.
struct OiiQTPlaceholder: View {
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
            OiiQTPlaceholder()
            Image(systemName: "dot.radiowaves.up.forward")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }
}
