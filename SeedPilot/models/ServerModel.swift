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
let torrentByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false // Prevents "Zero KB"
    return formatter
}()

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

    init(name: String, type: ServerType, address: String, port: Int, username: String, password: String, allowInsecureSSL: Bool = false) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.address = address
        self.port = port
        self.username = username
        self.password = password
        self.allowInsecureSSL = allowInsecureSSL
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

    // MARK: - Computed Properties

    /// 例如 "1.2 GB"
    var sizeString: String {
        torrentByteFormatter.string(fromByteCount: size)
    }

    var speedString: String {
        let dl = torrentByteFormatter.string(fromByteCount: downloadSpeed)
        let ul = torrentByteFormatter.string(fromByteCount: uploadSpeed)
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
        torrentByteFormatter.string(fromByteCount: downloaded)
    }

    var uploadedString: String {
        torrentByteFormatter.string(fromByteCount: uploaded)
    }

    var percentString: String {
        "\(Int(progress * 100))%"
    }

    /// 存储路径最后一级目录名
    var savePathShort: String {
        let trimmed = savePath.hasSuffix("/") ? String(savePath.dropLast()) : savePath
        return (trimmed as NSString).lastPathComponent
    }
}

// MARK: - 4. 抽象客户端协议
/// 定义了管理器必须实现的功能
protocol TorrentClient {
    // 登录认证 (qB 需要获取 Cookie，TR 需要获取 Session ID)
    func login() async throws

    // 获取任务列表
    func fetchTorrents() async throws -> [TorrentTask]

    // 添加磁力链接
    func addMagnetLink(_ link: String) async throws

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