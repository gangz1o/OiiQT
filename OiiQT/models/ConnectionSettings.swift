import Foundation

struct ConnectionSettings: Equatable, Sendable {
    var listenPort: Int
    var useUPnP: Bool
    /// Global max peers. `-1` or `0` means unlimited/disabled by server semantics.
    var maxConnections: Int
    var maxConnectionsPerTorrent: Int
    /// Transmission RPC does not support these upload slot settings.
    var maxUploads: Int?
    var maxUploadsPerTorrent: Int?
    /// 0 = TCP+uTP, 1 = TCP, 2 = uTP
    var bittorrentProtocol: Int

    // qBittorrent queue settings
    var torrentQueueEnabled: Bool? = nil
    var maxActiveDownloads: Int? = nil
    var maxActiveUploads: Int? = nil
    var maxActiveTorrents: Int? = nil

    // Transmission queue settings
    var downloadQueueEnabled: Bool? = nil
    var downloadQueueSize: Int? = nil
    var seedQueueEnabled: Bool? = nil
    var seedQueueSize: Int? = nil
    var queueStalledEnabled: Bool? = nil
    var queueStalledMinutes: Int? = nil
}
