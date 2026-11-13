import Foundation
import SwiftUI
import SwiftData

// MARK: - 1. 服务器类型与状态
enum ServerType: String, Codable, CaseIterable, Sendable {
    case qBittorrent = "qBittorrent"
    case transmission = "Transmission"
}

enum ServerConnectionState: String, Codable, Hashable, Sendable {
    case pending
    case online
    case offline

    nonisolated var isOnline: Bool? {
        switch self {
        case .pending:
            return nil
        case .online:
            return true
        case .offline:
            return false
        }
    }

    nonisolated var indicatorColor: Color {
        switch self {
        case .pending:
            return .orange
        case .online:
            return .green
        case .offline:
            return .red
        }
    }

    nonisolated var statusMessage: String {
        switch self {
        case .pending:
            return "连接中"
        case .online:
            return "在线"
        case .offline:
            return "连接异常"
        }
    }
}

enum TorrentStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case downloading = "下载中"
    case queued = "排队中"
    case seeding = "做种中"
    case paused = "已暂停"
    case checking = "校验中"
    case error = "错误"
    case completed = "已完成"

    var color: Color {
        switch self {
        case .downloading: return .blue
        case .queued: return .indigo
        case .seeding: return .green
        case .paused: return .gray
        case .checking: return .orange
        case .error: return .red
        case .completed: return .secondary
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .downloading:
            return LanguageManager.shared.localized("Downloading")
        case .queued:
            let localized = LanguageManager.shared.localized("Queued")
            return localized == "Queued" ? rawValue : localized
        case .seeding:
            return LanguageManager.shared.localized("Seeding")
        case .paused:
            return LanguageManager.shared.localized("Paused")
        case .checking:
            return LanguageManager.shared.localized("Checking")
        case .error:
            return LanguageManager.shared.localized("Error")
        case .completed:
            return LanguageManager.shared.localized("Completed")
        }
    }
}

// Helper Formatter
// Helper Formatter
// Helper Formatter
enum FormatHelper {
    private static let formatterLock = NSLock()

    static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static let ratioFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        formatter.locale = .current
        return formatter
    }()

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        formatterLock.lock()
        let formatted = byteCountFormatter.string(fromByteCount: bytes)
        formatterLock.unlock()
        return formatted
            .replacingOccurrences(of: "TiB", with: "TB")
            .replacingOccurrences(of: "GiB", with: "GB")
            .replacingOccurrences(of: "MiB", with: "MB")
            .replacingOccurrences(of: "KiB", with: "KB")
            .replacingOccurrences(of: "bytes", with: "B")
            .replacingOccurrences(of: "byte", with: "B")
            .replacingOccurrences(of: "字节", with: "B")
    }

    static func formatRatio(_ ratio: Double) -> String {
        formatterLock.lock()
        let formatted = ratioFormatter.string(from: NSNumber(value: ratio))
        formatterLock.unlock()
        return formatted ?? String(format: "%.2f", ratio)
    }

    static func formatPercent(_ progress: Double) -> String {
        "\(Int(progress * 100))%"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        return String(
            format: LanguageManager.shared.localized("Duration Day Hour Minute Format"),
            locale: .current,
            days,
            hours,
            minutes
        )
    }

    static func displayTitle(from rawTitle: String) -> String {
        rawTitle.replacingOccurrences(of: ".", with: ".\u{200B}")
    }
}

func formatBytes(_ bytes: Int64) -> String {
    FormatHelper.formatBytes(bytes)
}

func formatRatio(_ ratio: Double) -> String {
    FormatHelper.formatRatio(ratio)
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
    var useHTTPS: Bool = false
    var allowInsecureSSL: Bool = false
    var rpcPath: String = "/transmission/rpc"

    init(
        name: String,
        type: ServerType,
        address: String,
        port: Int,
        username: String,
        password: String,
        useHTTPS: Bool = false,
        allowInsecureSSL: Bool = false,
        rpcPath: String = "/transmission/rpc"
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.address = address
        self.port = port
        self.username = username
        self.password = password
        self.useHTTPS = useHTTPS
        self.allowInsecureSSL = allowInsecureSSL
        self.rpcPath = rpcPath
    }

    // Statistics
    var totalSeedingCount: Int = 0
    var totalDownloadingCount: Int = 0
    var totalSeedingSize: Int64 = 0
    var totalRatio: Double = 0.0

    // 计算属性：生成基础 URL
    @Transient
    var baseURL: String {
        "\(urlScheme)://\(sanitizedAddress):\(port)"
    }

    @Transient
    var sanitizedAddress: String {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()

        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            if let url = URL(string: raw), let host = url.host, !host.isEmpty {
                return host
            }
        }

        var trimmed = raw
        if lower.hasPrefix("https://") {
            trimmed = String(raw.dropFirst(8))
        } else if lower.hasPrefix("http://") {
            trimmed = String(raw.dropFirst(7))
        }

        if let slash = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slash])
        }

        if !trimmed.hasPrefix("["),
           let colon = trimmed.lastIndex(of: ":"),
           colon != trimmed.startIndex {
            let hostPart = String(trimmed[..<colon])
            let portPart = String(trimmed[trimmed.index(after: colon)...])
            if Int(portPart) != nil, !hostPart.isEmpty {
                return hostPart
            }
        }

        return trimmed
    }

    @Transient
    var urlScheme: String {
        let lower = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("https://") { return "https" }
        if lower.hasPrefix("http://") { return "http" }
        return useHTTPS ? "https" : "http"
    }

    /// 连接状态：pending=请求中, online=在线, offline=离线
    @Transient
    var connectionState: ServerConnectionState = .pending

    @Transient
    var consecutiveFailures: Int = 0

    @Transient
    var isOnline: Bool? {
        get { connectionState.isOnline }
        set {
            switch newValue {
            case true:
                connectionState = .online
            case false:
                connectionState = .offline
            case nil:
                connectionState = .pending
            }
        }
    }
}

extension ServerConfig {
    private static let connectionStateAnimation = Animation.easeInOut(duration: 0.3)
    private static let connectionFailureThreshold = 3

    @Transient
    var resolvedPassword: String {
        let securePassword = ServerCredentialStore.shared.password(for: id) ?? ""
        return securePassword.isEmpty ? password : securePassword
    }

    func setResolvedPassword(_ newPassword: String) throws {
        try ServerCredentialStore.shared.setPassword(newPassword, for: id)
        if !password.isEmpty {
            password = ""
        }
    }

    func deleteResolvedPassword() {
        ServerCredentialStore.shared.deletePassword(for: id)
        if !password.isEmpty {
            password = ""
        }
    }

    @MainActor
    func beginConnectionRefresh(isSilent: Bool) {
        guard !isSilent, connectionState != .online else { return }
        withAnimation(Self.connectionStateAnimation) {
            connectionState = .pending
        }
    }

    @MainActor
    func registerConnectionSuccess() {
        consecutiveFailures = 0
        guard connectionState != .online else { return }
        withAnimation(Self.connectionStateAnimation) {
            connectionState = .online
        }
    }

    @MainActor
    func registerConnectionFailure() {
        consecutiveFailures += 1

        guard consecutiveFailures >= Self.connectionFailureThreshold else {
            print("⚠️ 网络微小抖动，第 \(consecutiveFailures) 次失败，状态机保持原样 (防闪烁保护)")
            return
        }

        guard connectionState != .offline else { return }
        withAnimation(Self.connectionStateAnimation) {
            connectionState = .offline
        }
    }

    var statusColor: Color {
        connectionState.indicatorColor
    }
}

extension ServerConfig: Equatable {
    static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.type == rhs.type
    }
}

// MARK: - 3. 统一的任务模型 (UI 展现层)
/// 无论后端是 qB 还是 TR，UI 只看这个模型
enum ResolutionBadge: String, Codable, Hashable, Sendable {
    case ultraHD
    case fullHD
    case hd

    var text: String {
        switch self {
        case .ultraHD: return "4K"
        case .fullHD: return "1080p"
        case .hd: return "720p"
        }
    }

    var color: Color {
        switch self {
        case .ultraHD: return .purple
        case .fullHD: return .blue
        case .hd: return .green
        }
    }
}

struct TorrentTaskDisplayText: Hashable, Sendable {
    let title: String
    let percent: String
    let seedingTime: String
    let downloadSpeed: String
    let uploadSpeed: String
    let peers: String
    let seeds: String
    let size: String
    let ratio: String

    static func build(
        title: String,
        progress: Double,
        seedingTime: TimeInterval,
        downloadSpeed: Int64,
        uploadSpeed: Int64,
        numPeers: Int,
        totalPeers: Int,
        numSeeds: Int,
        totalSeeds: Int,
        size: Int64,
        ratio: Double
    ) -> TorrentTaskDisplayText {
        TorrentTaskDisplayText(
            title: FormatHelper.displayTitle(from: title),
            percent: FormatHelper.formatPercent(progress),
            seedingTime: FormatHelper.formatDuration(seedingTime),
            downloadSpeed: "\(FormatHelper.formatBytes(downloadSpeed))/s",
            uploadSpeed: "\(FormatHelper.formatBytes(uploadSpeed))/s",
            peers: "\(numPeers)/\(totalPeers)",
            seeds: "\(numSeeds)/\(totalSeeds)",
            size: FormatHelper.formatBytes(size),
            ratio: FormatHelper.formatRatio(ratio)
        )
    }
}

struct TorrentTask: Identifiable, Hashable, Sendable {
    let hash: String         // 原始任务 Hash（网络请求使用）
    let name: String         // 文件名
    let progress: Double     // 0.0 到 1.0
    let size: Int64          // 总大小 (Bytes)
    let downloadSpeed: Int64 // 每秒下载字节
    let uploadSpeed: Int64   // 每秒上传字节
    let remainingTime: TimeInterval // 剩余时间 (秒)
    let status: TorrentStatus
    let errorCode: Int?      // 后端错误码（Transmission）
    let errorMessage: String? // 后端错误信息（Transmission）或错误状态标识（qB）
    let serverID: UUID       // 所属服务器 ID
    let tracker: String      // Tracker URL
    let savePath: String     // 存储路径
    let category: String     // 分类 (qB)
    let tags: String         // 标签 (逗号分隔)
    let downloaded: Int64    // 已下载字节
    let uploaded: Int64      // 已上传字节
    let isSequential: Bool?  // 顺序下载 (Optional to support backward compat if needed, but better non-optional with default)
    let isFirstLastPiecePriority: Bool? // 首尾优先
    let completionDate: Date? // 完成时间

    // Task display fields
    let seedingTime: TimeInterval // 做种时间 (秒)
    let addedTime: Date           // 添加时间
    let resolutionBadge: ResolutionBadge?
    let displayText: TorrentTaskDisplayText
    let numSeeds: Int             // 连接种子数
    let totalSeeds: Int           // 总种子数
    let numPeers: Int             // 连接用户数
    let totalPeers: Int           // 总用户数
    let ratio: Double             // 分享率
    /// Pre-computed normalized tags for display — avoids split/dedup/sort on every SwiftUI body.
    let normalizedTags: [String]

    /// SwiftUI 渲染使用的复合 ID，避免多服务器聚合时 hash 冲突
    nonisolated var id: String {
        "\(serverID.uuidString)_\(hash)"
    }

    // MARK: - Computed Properties

    /// 例如 "1.2 GB"
    var sizeString: String {
        displayText.size
    }

    var speedString: String {
        "↓\(displayText.downloadSpeed) ↑\(displayText.uploadSpeed)"
    }

    /// 从 Tracker URL 提取域名，例如 "https://tracker.example.com/announce" → "tracker.example.com"
    nonisolated var trackerHost: String {
        let normalized = tracker
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        guard !normalized.isEmpty else { return "--" }

        if let url = URL(string: normalized), let host = url.host, !host.isEmpty {
            return host
        }

        var sanitized = normalized
        if let schemeRange = sanitized.range(of: "://") {
            sanitized = String(sanitized[schemeRange.upperBound...])
        }
        if let slashIndex = sanitized.firstIndex(of: "/") {
            sanitized = String(sanitized[..<slashIndex])
        }

        return sanitized.isEmpty ? "--" : sanitized
    }

    var downloadedString: String {
        formatBytes(downloaded)
    }

    var uploadedString: String {
        formatBytes(uploaded)
    }

    var percentString: String {
        displayText.percent
    }

    /// 存储路径最后一级目录名
    var savePathShort: String {
        let trimmed = savePath.hasSuffix("/") ? String(savePath.dropLast()) : savePath
        return (trimmed as NSString).lastPathComponent
    }

    var seedingTimeString: String {
        displayText.seedingTime
    }

    var ratioString: String {
        displayText.ratio
    }

    /// Normalize a raw comma/newline/semicolon-separated tags string into a
    /// sorted, deduplicated array. Called once at parse time on a background thread
    /// so the view body never has to do string processing.
    static func normalizeTags(from raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return Array(
            Set(
                raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    FormatHelper.formatDuration(seconds)
}

// MARK: - 3.5 种子文件模型

enum FilePriority: Int, Codable, CaseIterable, Hashable, Sendable {
    case doNotDownload = 0
    case normal = 1
    case high = 6
    case maximum = 7

    var localizedName: String {
        switch self {
        case .doNotDownload: return LanguageManager.shared.localized("Do Not Download")
        case .normal:        return LanguageManager.shared.localized("Normal")
        case .high:          return LanguageManager.shared.localized("High")
        case .maximum:       return LanguageManager.shared.localized("Maximum")
        }
    }

    var systemImage: String {
        switch self {
        case .doNotDownload: return "nosign"
        case .normal:        return "arrow.down.circle"
        case .high:          return "arrow.down.circle.fill"
        case .maximum:       return "flame.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .doNotDownload: return .gray
        case .normal:        return .blue
        case .high:          return .orange
        case .maximum:       return .red
        }
    }
}

struct TorrentFile: Identifiable, Hashable, Sendable {
    let index: Int
    let name: String
    let size: Int64
    let downloaded: Int64
    let progress: Double
    var priority: FilePriority

    var id: Int { index }

    var sizeString: String { FormatHelper.formatBytes(size) }
    var downloadedString: String { FormatHelper.formatBytes(downloaded) }

    var progressText: String {
        "\(downloadedString) / \(sizeString) (\(Int(progress * 100))%)"
    }

    var fileName: String {
        (name as NSString).lastPathComponent
    }
}

enum TorrentTrackerStatus: String, Codable, Hashable, Sendable {
    case working
    case updating
    case notContacted
    case failed
    case disabled
    case unknown

    var color: Color {
        switch self {
        case .working: return .green
        case .updating: return .blue
        case .notContacted: return .secondary
        case .failed: return .red
        case .disabled: return .gray
        case .unknown: return .secondary
        }
    }

    var localizedText: String {
        switch self {
        case .working:
            return LanguageManager.shared.localized("Working")
        case .updating:
            return LanguageManager.shared.localized("Updating")
        case .notContacted:
            return LanguageManager.shared.localized("Not Contacted")
        case .failed:
            return LanguageManager.shared.localized("Failed")
        case .disabled:
            return LanguageManager.shared.localized("Disabled")
        case .unknown:
            return LanguageManager.shared.localized("Unknown")
        }
    }
}

struct TorrentTrackerInfo: Identifiable, Hashable, Sendable {
    let id: String
    let tier: Int?
    let url: String
    let status: TorrentTrackerStatus
    let peers: Int?
    let seeds: Int?
    let leeches: Int?
    let downloaded: Int?
    let message: String?
}

struct TorrentPeerInfo: Identifiable, Hashable, Sendable {
    let id: String
    let country: String?
    let countryCode: String?
    let ip: String
    let port: Int
    let connection: String?
    let flags: String?
    let client: String?
    let progress: Double?
    let downloadSpeed: Int64?
    let uploadSpeed: Int64?
    let downloaded: Int64?
    let uploaded: Int64?
    let relevance: Double?
    let files: String?

    nonisolated var endpoint: String {
        "\(ip):\(port)"
    }
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

    // MARK: - File Management
    func getFiles(hash: String) async throws -> [TorrentFile]
    func setFilePriority(hash: String, fileIndices: [Int], priority: FilePriority) async throws

    // MARK: - Connection Settings
    func getConnectionSettings() async throws -> ConnectionSettings
    func setConnectionSettings(_ settings: ConnectionSettings) async throws

    // MARK: - Download Settings
    func getDownloadSettings() async throws -> DownloadSettings
    func setDownloadSettings(_ settings: DownloadSettings) async throws

    // MARK: - Batch Operations
    /// Batch pause. Pass `["all"]` to operate on every torrent.
    func pauseTasks(hashes: [String]) async throws
    /// Batch resume. Pass `["all"]` to operate on every torrent.
    func resumeTasks(hashes: [String]) async throws
    /// Batch delete. Pass `["all"]` to operate on every torrent.
    func deleteTasks(hashes: [String], withData: Bool) async throws
    /// Batch recheck.
    func recheckTasks(hashes: [String]) async throws
    /// Batch reannounce.
    func reannounceTasks(hashes: [String]) async throws
    /// Batch force start.
    func forceStartTasks(hashes: [String]) async throws
}
