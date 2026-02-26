import Foundation
import SwiftData

@MainActor
final class RSSFeedSourceCloudSyncManager {
    static let shared = RSSFeedSourceCloudSyncManager()

    private enum Keys {
        static let cloudPayload = "rssFeedSourceConfigsPayloadV1"
        static let localMutationTime = "rssFeedSourceConfigsLocalMutationTime"
    }

    private struct CloudPayload: Codable {
        let version: Int
        let updatedAt: Date
        let sources: [CloudSourceRecord]
    }

    // RSS config only: do NOT sync items/unread cache/runtime refresh timestamps.
    private struct CloudSourceRecord: Codable, Hashable {
        let id: UUID
        let name: String
        let url: String
        let isEnabled: Bool
        let autoDownload: Bool
        let faviconUrl: String?
        let includeKeywords: [String]
        let excludeKeywords: [String]
        let minSizeGB: Double?
        let maxSizeGB: Double?
        let targetServerId: UUID?
        let savePath: String
        let category: String
        let addPaused: Bool
        let priority: Int
        let episodeFilter: String
    }

    private enum Constants {
        static let payloadVersion = 1
    }

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private var modelContext: ModelContext?
    private var hasStarted = false
    private var isApplyingCloudChanges = false
    private var observers: [NSObjectProtocol] = []

    private init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
    }

    func start(with modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !hasStarted else { return }
        hasStarted = true

        let cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: nil
        ) { [weak self] note in
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            Task { @MainActor [weak self] in
                self?.handleCloudStoreChanged(changedKeys: changedKeys)
            }
        }

        observers.append(cloudObserver)
    }

    func reconcileOnLaunchOrBecomeActive() {
        guard isSyncEnabled else { return }
        guard ensureICloudAvailable() else { return }
        _ = cloudStore.synchronize()
        reconcileLocalAndCloud()
    }

    func handleSyncToggleChanged(enabled: Bool) {
        guard enabled else { return }
        guard ensureICloudAvailable() else { return }
        _ = cloudStore.synchronize()
        reconcileLocalAndCloud()
    }

    func handleLocalSourceConfigsChanged() {
        guard !isApplyingCloudChanges else { return }
        defaults.set(Date(), forKey: Keys.localMutationTime)
        pushLocalConfigsToCloudIfNeeded()
    }

    private var isSyncEnabled: Bool {
        defaults.bool(forKey: "iCloudSyncEnabled")
    }

    private func handleCloudStoreChanged(changedKeys: [String]?) {
        guard isSyncEnabled else { return }
        guard ensureICloudAvailable() else { return }

        if let changedKeys, !changedKeys.contains(Keys.cloudPayload) {
            return
        }

        applyCloudPayloadIfNeeded()
    }

    private func reconcileLocalAndCloud() {
        guard let modelContext else { return }

        let localSources = fetchLocalSources(context: modelContext)
        let localRecords = makeRecords(from: localSources)
        let localSignature = signature(for: localRecords)
        let cloudPayload = readCloudPayload()

        guard let cloudPayload else {
            if !localRecords.isEmpty {
                writeCloudPayload(sources: localRecords)
            }
            return
        }

        let cloudSignature = signature(for: cloudPayload.sources)
        if localSignature == cloudSignature {
            return
        }

        if localRecords.isEmpty {
            applyCloudPayloadIfNeeded()
            return
        }

        let localMutationTime = defaults.object(forKey: Keys.localMutationTime) as? Date
        let shouldPullCloud = (localMutationTime ?? .distantPast) < cloudPayload.updatedAt

        if shouldPullCloud {
            applyCloudPayloadIfNeeded()
        } else {
            writeCloudPayload(sources: localRecords)
        }
    }

    private func pushLocalConfigsToCloudIfNeeded() {
        guard let modelContext else { return }
        guard isSyncEnabled else { return }
        guard ensureICloudAvailable() else { return }

        let localRecords = makeRecords(from: fetchLocalSources(context: modelContext))
        let cloudRecords = readCloudPayload()?.sources ?? []
        guard signature(for: localRecords) != signature(for: cloudRecords) else { return }

        writeCloudPayload(sources: localRecords)
    }

    private func applyCloudPayloadIfNeeded() {
        guard let modelContext else { return }
        guard let payload = readCloudPayload() else { return }

        let localRecords = makeRecords(from: fetchLocalSources(context: modelContext))
        guard signature(for: localRecords) != signature(for: payload.sources) else { return }

        isApplyingCloudChanges = true
        defer { isApplyingCloudChanges = false }

        applyRecords(payload.sources, to: modelContext)
        defaults.set(payload.updatedAt, forKey: Keys.localMutationTime)
    }

    private func fetchLocalSources(context: ModelContext) -> [RSSFeedSource] {
        let descriptor = FetchDescriptor<RSSFeedSource>()
        let sources = (try? context.fetch(descriptor)) ?? []
        return sources.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func makeRecords(from sources: [RSSFeedSource]) -> [CloudSourceRecord] {
        sources
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { source in
                CloudSourceRecord(
                    id: source.id,
                    name: source.name,
                    url: source.url,
                    isEnabled: source.isEnabled,
                    autoDownload: source.autoDownload,
                    faviconUrl: source.faviconUrl,
                    includeKeywords: source.includeKeywords,
                    excludeKeywords: source.excludeKeywords,
                    minSizeGB: source.minSizeGB,
                    maxSizeGB: source.maxSizeGB,
                    targetServerId: source.targetServerId,
                    savePath: source.savePath,
                    category: source.category,
                    addPaused: source.addPaused,
                    priority: source.priority,
                    episodeFilter: source.episodeFilter
                )
            }
    }

    private func applyRecords(_ records: [CloudSourceRecord], to context: ModelContext) {
        let existing = fetchLocalSources(context: context)
        var existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))

        for record in records {
            if let source = existingByID.removeValue(forKey: record.id) {
                update(source, from: record)
            } else {
                context.insert(makeSource(from: record))
            }
        }

        for stale in existingByID.values where !incomingIDs.contains(stale.id) {
            context.delete(stale)
        }

        try? context.save()
    }

    private func update(_ source: RSSFeedSource, from record: CloudSourceRecord) {
        source.name = record.name
        source.url = record.url
        source.isEnabled = record.isEnabled
        source.autoDownload = record.autoDownload
        source.faviconUrl = record.faviconUrl
        source.includeKeywords = record.includeKeywords
        source.excludeKeywords = record.excludeKeywords
        source.minSizeGB = record.minSizeGB
        source.maxSizeGB = record.maxSizeGB
        source.targetServerId = record.targetServerId
        source.savePath = record.savePath
        source.category = record.category
        source.addPaused = record.addPaused
        source.priority = record.priority
        source.episodeFilter = record.episodeFilter
    }

    private func makeSource(from record: CloudSourceRecord) -> RSSFeedSource {
        let source = RSSFeedSource(
            name: record.name,
            url: record.url,
            isEnabled: record.isEnabled,
            lastUpdated: Date(),
            autoDownload: record.autoDownload,
            unreadCount: 0,
            faviconUrl: record.faviconUrl,
            includeKeywords: record.includeKeywords,
            excludeKeywords: record.excludeKeywords
        )
        source.id = record.id
        source.minSizeGB = record.minSizeGB
        source.maxSizeGB = record.maxSizeGB
        source.targetServerId = record.targetServerId
        source.savePath = record.savePath
        source.category = record.category
        source.addPaused = record.addPaused
        source.priority = record.priority
        source.episodeFilter = record.episodeFilter
        return source
    }

    private func readCloudPayload() -> CloudPayload? {
        if let data = cloudStore.data(forKey: Keys.cloudPayload) {
            return try? Self.decoder.decode(CloudPayload.self, from: data)
        }

        if let dict = cloudStore.dictionary(forKey: Keys.cloudPayload),
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let payload = try? Self.decoder.decode(CloudPayload.self, from: data) {
            return payload
        }

        return nil
    }

    private func writeCloudPayload(sources: [CloudSourceRecord]) {
        let payload = CloudPayload(version: Constants.payloadVersion, updatedAt: Date(), sources: sources)
        guard let data = try? Self.encoder.encode(payload) else { return }
        cloudStore.set(data, forKey: Keys.cloudPayload)
        cloudStore.synchronize()
    }

    private func signature(for records: [CloudSourceRecord]) -> Data? {
        try? Self.encoder.encode(records.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func ensureICloudAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
