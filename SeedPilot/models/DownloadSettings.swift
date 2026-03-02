import Foundation

struct DownloadSettings: Equatable, Sendable {
    var savePath: String
    var appendExtension: Bool
    var useTempPath: Bool
    var tempPath: String

    // qBittorrent-specific
    var preallocateAll: Bool?

    // Transmission-specific
    var cacheSizeMB: Int?
}
