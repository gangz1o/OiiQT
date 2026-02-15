import Foundation
import SwiftUI
import SwiftData

// MARK: - 1. 服务器类型与状态
enum ServerType: String, Codable, CaseIterable {
    case qBittorrent = "qBittorrent"
    case transmission = "Transmission"
}

enum TorrentStatus: String, Codable, CaseIterable {
    case downloading = "下载中"
    case seeding = "做种中"
    case paused = "已暂停"
    case checking = "校验中"
    case error = "错误"
    case completed = "已完成"

    var color: Color {
        switch self {
        case .downloading: return .blue
        case .seeding: return .green
        case .paused: return .gray
        case .error: return .red
        default: return .secondary
        }
    }
}

// Helper Formatter
// Helper Formatter
// Helper Formatter
let torrentByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter
}()

func formatBytes(_ bytes: Int64) -> String {
    if bytes == 0 { return "0 B" }
    let formatted = torrentByteFormatter.string(fromByteCount: bytes)
    return formatted.replacingOccurrences(of: "bytes", with: "B")
}

// MARK: - 2. 服务器配置模型
@Model
final class ServerConfig {
    var id: UUID = UUID()
    var name: String = ""
    var type: ServerType = ServerType.qBittorrent
    var address: String = ""
    var port: Int = 8080
    var username: String = ""
    var password: String = ""
    var allowInsecureSSL: Bool = false
    var rpcPath: String = "/transmission/rpc"

    init(name: String, type: ServerType, address: String, port: Int, username: String, password: String, allowInsecureSSL: Bool = false, rpcPath: String = "/transmission/rpc") {
        self.id = UUID()
        self.name = name
        self.type = type
        self.address = address
        self.port = port
        self.username = username
        self.password = password
        self.allowInsecureSSL = allowInsecureSSL
        self.rpcPath = rpcPath
    }

    // 计算属性：生成基础 URL
    @Transient
    var baseURL: String {
        "\(address):\(port)"
    }

    /// 在线状态：nil=检测中, true=在线, false=离线
    @Transient
    var isOnline: Bool? = nil
}

extension ServerConfig {
    var statusColor: Color {
        switch isOnline {
        case true: return .green
        case false: return .red
        case nil: return .gray
        }
    }
}

// MARK: - 3. 统一的任务模型 (UI 展现层)
/// 无论后端是 qB 还是 TR，UI 只看这个模型
struct TorrentTask: Identifiable, Hashable {
    let id: String           // 任务的 Hash 值
    let name: String         // 文件名
    let progress: Double     // 0.0 到 1.0
    let size: Int64          // 总大小 (Bytes)
    let downloadSpeed: Int64 // 每秒下载字节
    let uploadSpeed: Int64   // 每秒上传字节
    let remainingTime: TimeInterval // 剩余时间 (秒)
    let status: TorrentStatus
    let serverID: UUID       // 所属服务器 ID
    let tracker: String      // Tracker URL
    let savePath: String     // 存储路径
    let tags: String         // 标签 (逗号分隔)
    let downloaded: Int64    // 已下载字节
    let uploaded: Int64      // 已上传字节
    let isSequential: Bool?  // 顺序下载 (Optional to support backward compat if needed, but better non-optional with default)
    let isFirstLastPiecePriority: Bool? // 首尾优先
    let completionDate: Date? // 完成时间

    // New Fields for Pro Display
    let seedingTime: TimeInterval // 做种时间 (秒)
    let addedTime: Date           // 添加时间
    let numSeeds: Int             // 连接种子数
    let totalSeeds: Int           // 总种子数
    let numPeers: Int             // 连接用户数
    let totalPeers: Int           // 总用户数
    let ratio: Double             // 分享率


    // MARK: - Computed Properties

    /// 例如 "1.2 GB"
    var sizeString: String {
        formatBytes(size)
    }

    var speedString: String {
        let dl = formatBytes(downloadSpeed)
        let ul = formatBytes(uploadSpeed)
        return "↓\(dl)/s ↑\(ul)/s"
    }

    /// 从 Tracker URL 提取域名，例如 "https://tracker.example.com/announce" → "tracker.example.com"
    var trackerHost: String {
        guard let url = URL(string: tracker), let host = url.host else {
            return tracker.isEmpty ? "--" : tracker
        }
        return host
    }

    var downloadedString: String {
        formatBytes(downloaded)
    }

    var uploadedString: String {
        formatBytes(uploaded)
    }

    var percentString: String {
        "\(Int(progress * 100))%"
    }

    /// 存储路径最后一级目录名
    var savePathShort: String {
        let trimmed = savePath.hasSuffix("/") ? String(savePath.dropLast()) : savePath
        return (trimmed as NSString).lastPathComponent
    }

    var seedingTimeString: String {
        formatDuration(seedingTime)
    }

    var ratioString: String {
        String(format: "%.2f", ratio)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .positional // HH:mm:ss
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: seconds) ?? "00:00:00"
}

// MARK: - 4. 抽象客户端协议
/// 定义了管理器必须实现的功能
protocol TorrentClient {
    // 登录认证 (qB 需要获取 Cookie，TR 需要获取 Session ID)
    func login() async throws

    // 获取任务列表
    func fetchTorrents() async throws -> [TorrentTask]

    // 添加任务
    func addTorrents(_ urls: [String], options: AddTorrentOptions) async throws
    func addTorrentFile(_ fileURL: URL, options: AddTorrentOptions) async throws

    // 控制命令
    func pauseTask(hash: String) async throws
    func resumeTask(hash: String) async throws
    func deleteTask(hash: String, withData: Bool) async throws

    // 心跳检测 (返回版本号或 true，失败抛出异常)
    func checkConnection() async throws -> String

    // MARK: - Advanced Management
    func recheckTask(hash: String) async throws
    func reannounceTask(hash: String) async throws
    func toggleSequentialDownload(hash: String) async throws
    func toggleFirstLastPiecePriority(hash: String) async throws
    func renameTask(hash: String, newName: String) async throws

    // MARK: - Core Control Logic
    func forceStartTask(hash: String) async throws
    func setLocation(hash: String, newLocation: String) async throws
    func editTrackers(hash: String, newTrackers: String) async throws
}