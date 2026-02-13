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
    
    init(name: String, type: ServerType, address: String, port: Int, username: String, password: String) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.address = address
        self.port = port
        self.username = username
        self.password = password
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
    
    // 辅助格式化：例如 "1.2 GB"
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var speedString: String {
        let dl = ByteCountFormatter.string(fromByteCount: downloadSpeed, countStyle: .file)
        let ul = ByteCountFormatter.string(fromByteCount: uploadSpeed, countStyle: .file)
        return "↓\(dl)/s ↑\(ul)/s"
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
}