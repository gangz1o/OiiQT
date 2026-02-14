//
//  ImageCacheManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import Foundation
import UIKit // For UIImage

class ImageCacheManager {
    static let shared = ImageCacheManager()

    // 1. 内存缓存 (NSCache)
    private let memoryCache = NSCache<NSString, UIImage>()

    // 2. 磁盘缓存配置
    private let fileManager = FileManager.default
    private let diskCacheDirectory: URL

    private init() {
        // Setup Memory Cache limits
        memoryCache.countLimit = 100 // Max 100 images
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        // Setup Disk Cache Directory
        let cacheURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let diskCacheURL = cacheURLs[0].appendingPathComponent("TMDBPosters")
        diskCacheDirectory = diskCacheURL

        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// 获取图片 (Memory -> Disk -> nil)
    func image(forKey key: String) -> UIImage? {
        // 1. Check Memory
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }

        // 2. Check Disk
        let fileURL = diskCacheDirectory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            // Restore to Memory
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }

        return nil
    }

    /// 保存图片 (Memory + Disk)
    func setImage(_ image: UIImage, forKey key: String) {
        // 1. Save to Memory
        memoryCache.setObject(image, forKey: key as NSString)

        // 2. Save to Disk (Async)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let fileURL = self.diskCacheDirectory.appendingPathComponent(key)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
            }
        }
    }

    /// 下载并在缓存中保存图片
    func downloadImage(url: URL, key: String) async -> UIImage? {
        // Check cache first
        if let cached = image(forKey: key) {
            return cached
        }

        // Download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                setImage(image, forKey: key)
                return image
            }
        } catch {
            print("Failed to download image: \(error)")
        }
        return nil
    }

    // MARK: - Maintenance

    /// 计算缓存大小 (Bytes)
    func calculateDiskCacheSize() -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        return contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    /// 清除所有缓存
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDirectory)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }
}
