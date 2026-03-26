//
//  CachedAsyncImage.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import Kingfisher
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private final class SeedPilotDoubanAuthenticationChallengeResponder: AuthenticationChallengeResponsible {
    func downloader(
        _ downloader: ImageDownloader,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challengeResponse(for: challenge)
    }

    func downloader(
        _ downloader: ImageDownloader,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challengeResponse(for: challenge)
    }

    private func challengeResponse(
        for challenge: URLAuthenticationChallenge
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              !challenge.protectionSpace.host.isEmpty,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host.lowercased()
        guard host.hasSuffix("doubanio.com") else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: serverTrust))
    }
}

enum SeedPilotImageLoading {
    static let processingQueue = DispatchQueue.global(qos: .userInitiated)
    private static let doubanAuthenticationResponder = SeedPilotDoubanAuthenticationChallengeResponder()
    fileprivate static let doubanDownloader: ImageDownloader = {
        let downloader = ImageDownloader(name: "seedpilot.douban")
        downloader.authenticationChallengeResponder = doubanAuthenticationResponder
        return downloader
    }()

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
}

extension KFOptionSetter {
    /// `size` uses point-based layout size. `scaleFactor` handles pixel density.
    func targetSize(_ size: CGSize, scale: CGFloat? = nil) -> Self {
        _ = scaleFactor(scale ?? SeedPilotImageLoading.displayScale)
        return downsampling(size: size)
    }

    func cacheOriginalImage(if enabled: Bool) -> Self {
        guard enabled else {
            return self
        }

        return cacheOriginalImage()
    }

    func seedPilotDownloader(for url: URL?) -> Self {
        guard SeedPilotImageLoading.needsDoubanHeaders(for: url) else {
            return self
        }

        #if targetEnvironment(simulator)
        return downloader(SeedPilotImageLoading.doubanDownloader)
        #else
        return self
        #endif
    }

    func seedPilotRequestHeaders(for url: URL?) -> Self {
        guard SeedPilotImageLoading.needsDoubanHeaders(for: url) else {
            return self
        }

        return requestModifier { request in
            request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
    }
}

// MARK: - Unified Image Component

/// Drop-in replacement for AsyncImage, powered by Kingfisher.
/// Handles memory + disk caching, fade-in animation, and smooth gradient placeholders.
struct SimpleCachedImage: View {
    let url: URL?
    var downsampleSize: CGSize? = nil
    var cacheOriginal: Bool = true

    var body: some View {
        if let downsampleSize {
            KFImage(url)
                .placeholder { SeedPilotPlaceholder() }
                .seedPilotDownloader(for: url)
                .seedPilotRequestHeaders(for: url)
                .targetSize(downsampleSize)
                .backgroundDecode(true)
                .processingQueue(.dispatch(SeedPilotImageLoading.processingQueue))
                .cacheOriginalImage(if: cacheOriginal)
                .fade(duration: 0.2)
                .cancelOnDisappear(true)
                .resizable()
        } else {
            KFImage(url)
                .placeholder { SeedPilotPlaceholder() }
                .seedPilotDownloader(for: url)
                .seedPilotRequestHeaders(for: url)
                .cacheOriginalImage(if: cacheOriginal)
                .backgroundDecode(true)
                .processingQueue(.dispatch(SeedPilotImageLoading.processingQueue))
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
                    .seedPilotDownloader(for: url)
                    .seedPilotRequestHeaders(for: url)
                    .cacheOriginalImage(if: false)
                    .backgroundDecode(true)
                    .processingQueue(.dispatch(SeedPilotImageLoading.processingQueue))
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
