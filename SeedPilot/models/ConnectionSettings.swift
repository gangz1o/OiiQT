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
}
