import Foundation

nonisolated private let moviePilotEnglishOverrides: [String: String] = [
    "发现": "Discover",
    "搜索 电影/剧集": "Search movies/series",
    "没有匹配的内容": "No matching content",
    "试试其他关键词或分类。": "Try different keywords or categories.",
    "无法打开列表": "Unable to open list",
    "当前分区暂时不可用。": "This section is currently unavailable.",
    "无法执行搜索": "Unable to search",
    "请先配置可用的 MoviePilot 服务器。": "Please configure an available MoviePilot server first.",
    "暂无内容": "No content available",
    "稍后重试或下拉刷新。": "Try again later or pull to refresh.",
    "搜索失败": "Search failed",
    "更多": "More",
    "正在加载更多": "Loading more",
    "加载更多": "Load more",
    "根据 MoviePilot 当前服务器能力动态生成订阅配置。": "Subscription settings are generated from current MoviePilot server capabilities.",
    "取消": "Cancel",
    "不限制": "No limit",
    "搜索": "Search",
    "已订阅": "Subscribed",
    "订阅": "Subscribe",
    "暂无评分": "No rating",
    "简介": "Overview",
    "暂无简介": "No overview available",
    "收起": "Collapse",
    "展开": "Expand",
    "正在同步详情": "Syncing details",
    "搜索结果": "Search Results",
    "筛选与排序": "Filters & Sort",
    "正在检索站点资源": "Searching site resources",
    "还没有资源结果": "No results yet",
    "点击下方搜索按钮后会显示结果。": "Results will appear after tapping Search below.",
    "没有符合条件的资源": "No resources match current filters",
    "调整筛选条件后再试。": "Adjust filters and try again.",
    "在浏览器中打开": "Open in Browser",
    "资源": "Resource",
    "正在加载下载器…": "Loading downloaders...",
    "下载器": "Downloader",
    "留空使用默认路径": "Leave empty to use default path",
    "使用默认路径": "Use Default Path",
    "选择预置目录": "Choose Preset Directory",
    "保存路径": "Save Path",
    "可选。留空将使用 MoviePilot 默认配置的保存路径。": "Optional. Leave empty to use the MoviePilot default save path.",
    "可选。可直接选择预置目录，或留空使用 MoviePilot 默认配置的保存路径。": "Optional. Choose a preset directory or leave empty to use the MoviePilot default save path.",
    "下载配置": "Download Settings",
    "下载": "Download",
    "站点": "Site",
    "全部站点": "All Sites",
    "资源规格": "Resource Specs",
    "分辨率": "Resolution",
    "全部分辨率": "All Resolutions",
    "片源": "Source",
    "全部片源": "All Sources",
    "编码": "Codec",
    "全部编码": "All Codecs",
    "高级筛选": "Advanced Filters",
    "仅显示促销资源": "Promotion Only",
    "隐藏 H&R 资源": "Hide H&R Resources",
    "排序": "Sort",
    "排序依据": "Sort By",
    "排序方向": "Sort Order",
    "重置": "Reset",
    "应用": "Apply",
    "全部": "All",
    "电影": "Movies",
    "电视剧": "TV Shows",
    "剧集": "Series",
    "动漫": "Anime",
    "Bangumi 每日放送": "Bangumi Daily Airing",
    "豆瓣正在热映": "Douban Now Playing",
    "豆瓣电影": "Douban Movies",
    "豆瓣剧集": "Douban TV Shows",
    "豆瓣电影 TOP250": "Douban Movie Top 250",
    "豆瓣国产剧集周榜": "Douban Chinese TV Weekly",
    "豆瓣全球剧集周榜": "Douban Global TV Weekly",
    "豆瓣动画剧集": "Douban Animation Series",
    "豆瓣热门电影": "Douban Hot Movies",
    "豆瓣热门剧集": "Douban Hot TV Shows",
    "TMDB 电影": "TMDB Movies",
    "TMDB 剧集": "TMDB TV Shows",
    "TMDB 流行趋势": "TMDB Trending",
    "筛选策略": "Filtering Strategy",
    "清晰度": "Quality",
    "例如：BluRay / WEB-DL": "e.g. BluRay / WEB-DL",
    "特效规格": "Effects",
    "例如：HDR / Dolby Vision": "e.g. HDR / Dolby Vision",
    "过滤规则": "Filter Rules",
    "填写服务端支持的过滤表达式": "Enter a server-supported filter expression",
    "包含关键词": "Include Keywords",
    "多个关键词用空格分隔": "Separate keywords with spaces",
    "排除关键词": "Exclude Keywords",
    "排除噪音版本或小组": "Exclude noisy versions or release groups",
    "自动洗版": "Auto Upgrade",
    "开启后允许按更优版本持续升级": "Enable continuous upgrades to better versions",
    "下载与归档": "Download & Archive",
    "使用当前 MoviePilot 可用下载器列表": "Use available downloaders from the current MoviePilot server",
    "自动分类": "Auto Category",
    "读取服务器自动分类配置": "Use server auto-category configuration",
    "存储路径": "Storage Path",
    "例如：/downloads/media": "e.g. /downloads/media",
    "搜索控制": "Search Controls",
    "自定义识别词": "Custom Keywords",
    "补充别名、制作组或地区信息": "Add aliases, release groups, or region info",
    "优先使用 IMDb 搜索": "Prefer IMDb Search",
    "打开后会在搜索阶段带上 IMDb 识别信息": "Include IMDb identifiers during search when enabled",
    "订阅设置": "Subscription Settings",
    "编辑订阅": "Edit Subscription",
    "创建订阅": "Create Subscription",
    "更新订阅": "Update Subscription",
    "当前媒体已存在订阅，可直接调整策略。": "Subscription already exists for this media. You can update strategy directly.",
    "请先配置 MoviePilot 服务器。": "Please configure a MoviePilot server first.",
    "正在搜索资源...": "Searching resources...",
    "下载失败，请重试。": "Download failed, please try again.",
    "订阅提交失败": "Subscription submission failed",
    "没有找到匹配资源。": "No matching resources found.",
    "未知标题": "Unknown Title",
    "未知演员": "Unknown Actor",
    "大小未知": "Unknown Size",
    "未知站点": "Unknown Site",
    "未知资源": "Unknown Resource",
    "暂无副标题": "No Subtitle",
    "时间未知": "Unknown Time",
    "免费": "Free",
    "上映": "Release",
    "导演": "Director",
    "演员": "Cast",
    "类型": "Genre",
    "详情": "Details",
    "正在载入...": "Loading...",
    "默认": "Relevance",
    "做种数": "Seeders",
    "发布时间": "Publish Time",
    "文件大小": "File Size",
    "降序": "Descending",
    "升序": "Ascending"
]

nonisolated private let moviePilotCountPatternWithFiltered = try? NSRegularExpression(
    pattern: #"^已找到\s*(\d+)\s*个候选资源（已过滤\s*(\d+)\s*条无效记录）$"#,
    options: []
)

nonisolated private let moviePilotCountPattern = try? NSRegularExpression(
    pattern: #"^已找到\s*(\d+)\s*个候选资源$"#,
    options: []
)

nonisolated private let moviePilotSeasonPattern = try? NSRegularExpression(
    pattern: #"^第\s*(\d+)\s*季$"#,
    options: []
)

nonisolated func moviePilotLocalized(_ text: String) -> String {
    let persistedCode = UserDefaults.standard.string(forKey: "language")
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
    let isSystemChinese = preferred.hasPrefix("zh")
    let currentCode = persistedCode ?? (isSystemChinese ? "zh-Hans" : "en")
    let isEnglish = currentCode == "en"

    let bundle: Bundle
    if let path = Bundle.main.path(forResource: currentCode, ofType: "lproj"), let b = Bundle(path: path) {
        bundle = b
    } else {
        bundle = .main
    }

    let localized = NSLocalizedString(text, tableName: nil, bundle: bundle, value: text, comment: "")

    guard isEnglish else {
        return localized
    }

    if localized != text {
        return localized
    }

    if let mapped = moviePilotEnglishOverrides[text] {
        return mapped
    }

    if let dynamic = moviePilotDynamicEnglishTranslation(for: text) {
        return dynamic
    }

    return text
}

nonisolated private func moviePilotDynamicEnglishTranslation(for text: String) -> String? {
    let fullRange = NSRange(text.startIndex..., in: text)

    if let pattern = moviePilotCountPatternWithFiltered,
       let match = pattern.firstMatch(in: text, options: [], range: fullRange),
       let countRange = Range(match.range(at: 1), in: text),
       let filteredRange = Range(match.range(at: 2), in: text) {
        let count = String(text[countRange])
        let filtered = String(text[filteredRange])
        return "Found \(count) candidate resources (filtered \(filtered) invalid records)"
    }

    if let pattern = moviePilotCountPattern,
       let match = pattern.firstMatch(in: text, options: [], range: fullRange),
       let countRange = Range(match.range(at: 1), in: text) {
        let count = String(text[countRange])
        return "Found \(count) candidate resources"
    }

    if let pattern = moviePilotSeasonPattern,
       let match = pattern.firstMatch(in: text, options: [], range: fullRange),
       let seasonRange = Range(match.range(at: 1), in: text) {
        let season = String(text[seasonRange])
        return "Season \(season)"
    }

    return nil
}
