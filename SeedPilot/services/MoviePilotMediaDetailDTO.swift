import Foundation

typealias MPMediaDetailDTO = MPMediaItemDTO
typealias MPMediaPersonListDTO = [MPMediaPersonDTO]
typealias MPTorrentListDTO = [MPTorrentInfoDTO]
typealias MPSearchContextListDTO = [MPSearchContextDTO]
typealias MPDownloadClientListDTO = [MPDownloadClientDTO]
typealias MPSiteListDTO = [MPSiteDTO]

/// API 搜索返回的上下文包装，对应 openapi.json 中的 Context schema。
/// 搜索结果的 TorrentInfo 嵌套在 `torrent_info` 键内。
nonisolated struct MPSearchContextDTO: Decodable, Sendable {
    let torrentInfo: MPTorrentInfoDTO?

    enum CodingKeys: String, CodingKey {
        case torrentInfo = "torrent_info"
    }
}

/// 配对：类型化 DTO + 原始 JSON Data（供 download/add 回传）
nonisolated struct MPSearchResultWithRawDTO: Sendable {
    let torrentInfo: MPTorrentInfoDTO
    let rawTorrentInfoJSON: Data
}

nonisolated struct MPMediaPersonDTO: Decodable, Sendable, Equatable {
    let source: String?
    let id: Int?
    let name: String?
    let character: String?
    let profilePath: String?
    let avatarURLString: String?

    enum CodingKeys: String, CodingKey {
        case source
        case id
        case name
        case character
        case profilePath = "profile_path"
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = container.decodeLossyString(forKey: .source)
        id = container.decodeLossyInt(forKey: .id)
        name = container.decodeLossyString(forKey: .name)
        character = container.decodeLossyString(forKey: .character)
        profilePath = container.decodeLossyString(forKey: .profilePath)
        avatarURLString = try Self.decodeAvatarURL(from: container, forKey: .avatar)
    }

    private static func decodeAvatarURL(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        if let stringValue = container.decodeLossyString(forKey: key) {
            return stringValue
        }

        guard let avatarObject = try? container.decodeIfPresent([String: String].self, forKey: key) else {
            return nil
        }

        let preferredKeys = ["large", "medium", "small", "normal", "avatar", "url"]
        for preferredKey in preferredKeys {
            if let value = avatarObject[preferredKey], !value.isEmpty {
                return value
            }
        }

        return avatarObject.values.first(where: { !$0.isEmpty })
    }
}

nonisolated struct MPTorrentInfoDTO: Codable, Sendable, Equatable {
    let site: Int?
    let siteName: String?
    let title: String?
    let description: String?
    let imdbID: String?
    let pageURL: String?
    let size: Double?
    let seeders: Int?
    let peers: Int?
    let grabs: Int?
    let pubdate: String?
    let dateElapsed: String?
    let uploadVolumeFactor: Double?
    let downloadVolumeFactor: Double?
    let hitAndRun: Bool?
    let priOrder: Int?
    let volumeFactor: String?
    let freeDateDiff: String?
    let labels: [String]

    enum CodingKeys: String, CodingKey {
        case site
        case siteName = "site_name"
        case title
        case description
        case imdbID = "imdbid"
        case pageURL = "page_url"
        case size
        case seeders
        case peers
        case grabs
        case pubdate
        case dateElapsed = "date_elapsed"
        case uploadVolumeFactor = "uploadvolumefactor"
        case downloadVolumeFactor = "downloadvolumefactor"
        case hitAndRun = "hit_and_run"
        case priOrder = "pri_order"
        case volumeFactor = "volume_factor"
        case freeDateDiff = "freedate_diff"
        case labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        site = container.decodeLossyInt(forKey: .site)
        siteName = container.decodeLossyString(forKey: .siteName)
        title = container.decodeLossyString(forKey: .title)
        description = container.decodeLossyString(forKey: .description)
        imdbID = container.decodeLossyString(forKey: .imdbID)
        pageURL = container.decodeLossyString(forKey: .pageURL)
        size = container.decodeLossyDouble(forKey: .size)
        seeders = container.decodeLossyInt(forKey: .seeders)
        peers = container.decodeLossyInt(forKey: .peers)
        grabs = container.decodeLossyInt(forKey: .grabs)
        pubdate = container.decodeLossyString(forKey: .pubdate)
        dateElapsed = container.decodeLossyString(forKey: .dateElapsed)
        uploadVolumeFactor = container.decodeLossyDouble(forKey: .uploadVolumeFactor)
        downloadVolumeFactor = container.decodeLossyDouble(forKey: .downloadVolumeFactor)
        hitAndRun = container.decodeLossyBool(forKey: .hitAndRun)
        priOrder = container.decodeLossyInt(forKey: .priOrder)
        volumeFactor = container.decodeLossyString(forKey: .volumeFactor)
        freeDateDiff = container.decodeLossyString(forKey: .freeDateDiff)
        labels = (try? container.decodeIfPresent([String].self, forKey: .labels)) ?? []
    }
}

nonisolated struct MPDownloadClientDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let subtitle: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let rawID = container.decodeLossyString(forKeys: ["id", "name", "type", "label", "client"])
        let rawName = container.decodeLossyString(forKeys: ["name", "label", "title", "client", "id"])
        let rawSubtitle = container.decodeLossyString(forKeys: ["type", "kind", "category", "class"])

        id = rawID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? rawID!.trimmingCharacters(in: .whitespacesAndNewlines)
            : UUID().uuidString
        name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? rawName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "默认下载器"
        subtitle = rawSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

nonisolated struct MPSiteDTO: Decodable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let url: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id)
        name = container.decodeLossyString(forKey: .name)
        url = container.decodeLossyString(forKey: .url)
        isActive = container.decodeLossyBool(forKey: .isActive)
    }
}

nonisolated enum MPJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MPJSONValue])
    case array([MPJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MPJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MPJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

nonisolated struct MPSubscribeDTO: Codable, Sendable, Equatable {
    var id: Int? = nil
    var name: String? = nil
    var year: String? = nil
    var type: String? = nil
    var keyword: String? = nil
    var tmdbid: Int? = nil
    var doubanid: String? = nil
    var bangumiid: Int? = nil
    var mediaid: String? = nil
    var season: Int? = nil
    var poster: String? = nil
    var backdrop: String? = nil
    var vote: Double? = nil
    var description: String? = nil
    var filter: String? = nil
    var include: String? = nil
    var exclude: String? = nil
    var quality: String? = nil
    var resolution: String? = nil
    var effect: String? = nil
    var totalEpisode: Int? = nil
    var startEpisode: Int? = nil
    var lackEpisode: Int? = nil
    var note: MPJSONValue? = nil
    var state: String? = nil
    var lastUpdate: String? = nil
    var username: String? = nil
    var sites: [Int]? = nil
    var downloader: String? = nil
    var bestVersion: Int? = nil
    var currentPriority: Int? = nil
    var savePath: String? = nil
    var searchImdbid: Int? = nil
    var date: String? = nil
    var customWords: String? = nil
    var mediaCategory: String? = nil
    var filterGroups: [String]? = nil
    var episodeGroup: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case year
        case type
        case keyword
        case tmdbid
        case doubanid
        case bangumiid
        case mediaid
        case season
        case poster
        case backdrop
        case vote
        case description
        case filter
        case include
        case exclude
        case quality
        case resolution
        case effect
        case totalEpisode = "total_episode"
        case startEpisode = "start_episode"
        case lackEpisode = "lack_episode"
        case note
        case state
        case lastUpdate = "last_update"
        case username
        case sites
        case downloader
        case bestVersion = "best_version"
        case currentPriority = "current_priority"
        case savePath = "save_path"
        case searchImdbid = "search_imdbid"
        case date
        case customWords = "custom_words"
        case mediaCategory = "media_category"
        case filterGroups = "filter_groups"
        case episodeGroup = "episode_group"
    }
}

nonisolated struct MPSubscriptionMutationDataDTO: Decodable, Sendable, Equatable {
    let id: Int?
}

nonisolated struct MoviePilotActionResponseDTO: Decodable, Sendable, Equatable {
    let success: Bool
    let message: String?
}

nonisolated struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == AnyCodingKey {
    nonisolated func decodeLossyString(forKeys keys: [String]) -> String? {
        for rawKey in keys {
            guard let key = AnyCodingKey(stringValue: rawKey) else { continue }

            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }

            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return String(value)
            }
        }

        return nil
    }
}

extension KeyedDecodingContainer {
    nonisolated func decodeLossyBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}
