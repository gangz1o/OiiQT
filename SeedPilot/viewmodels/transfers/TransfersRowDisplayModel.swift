import Foundation

struct TransfersRowDisplayOptions: Equatable, Sendable {
    let isProUser: Bool
    let hideTracker: Bool
    let serverTypeByID: [UUID: ServerType]
}

struct TransfersRowDisplayModel: Identifiable, Equatable, Sendable {
    let id: String
    let status: TorrentStatus
    let progress: Double
    let trackerText: String?
    let taxonomyTags: [String]
    let hiddenTaxonomyCount: Int
    let titleText: String
    let percentText: String
    let downloadSpeedText: String
    let uploadSpeedText: String
    let peersText: String
    let seedsText: String
    let sizeText: String
    let ratioText: String
    let seedingTimeText: String
    let savePathText: String
    let serverType: ServerType?
    let resolutionBadge: ResolutionBadge?

    nonisolated static func make(
        from task: TorrentTask,
        aliasMap: [String: String],
        options: TransfersRowDisplayOptions
    ) -> TransfersRowDisplayModel {
        let serverType = options.serverTypeByID[task.serverID]
        let trackerText: String?
        if options.hideTracker {
            trackerText = nil
        } else if options.isProUser,
                  let alias = aliasMap[task.trackerHost.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !alias.isEmpty {
            trackerText = alias
        } else {
            trackerText = task.trackerHost
        }

        let displayCategory: String?
        if let serverType, serverType != .transmission {
            let trimmedCategory = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
            displayCategory = trimmedCategory.isEmpty ? nil : trimmedCategory
        } else {
            displayCategory = nil
        }

        var taxonomyTags: [String] = []
        if let displayCategory {
            taxonomyTags.append(displayCategory)
        }

        let remainingTagCapacity = max(0, 2 - taxonomyTags.count)
        if remainingTagCapacity > 0 {
            taxonomyTags.append(contentsOf: task.normalizedTags.prefix(remainingTagCapacity))
        }

        let hiddenTaxonomyCount = max(0, (displayCategory == nil ? 0 : 1) + task.normalizedTags.count - 2)

        return TransfersRowDisplayModel(
            id: task.id,
            status: task.status,
            progress: task.progress,
            trackerText: trackerText,
            taxonomyTags: taxonomyTags,
            hiddenTaxonomyCount: hiddenTaxonomyCount,
            titleText: task.displayText.title,
            percentText: task.displayText.percent,
            downloadSpeedText: task.displayText.downloadSpeed,
            uploadSpeedText: task.displayText.uploadSpeed,
            peersText: task.displayText.peers,
            seedsText: task.displayText.seeds,
            sizeText: task.displayText.size,
            ratioText: task.displayText.ratio,
            seedingTimeText: task.displayText.seedingTime,
            savePathText: task.savePath.isEmpty ? "--" : task.savePath,
            serverType: serverType,
            resolutionBadge: task.resolutionBadge
        )
    }
}
