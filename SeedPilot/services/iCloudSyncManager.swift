import Foundation

extension Notification.Name {
    static let iCloudSyncStatusDidChange = Notification.Name("iCloudSyncStatusDidChange")
}

// WARNING: Server credentials (Passwords/Tokens) MUST use Keychain. NEVER add them to syncableKeys.
final class iCloudSyncManager {
    enum ErrorCode: String {
        case accountUnavailable
        case quotaExceeded
        case unknown
    }

    struct SyncStatus {
        let isEnabled: Bool
        let isSyncing: Bool
        let lastSuccessfulSync: Date?
        let lastErrorCode: ErrorCode?
    }

    static let shared = iCloudSyncManager()

    let syncableKeys: [String] = [
        "refreshRate",
        "rssRefreshInterval",
        "fontSize",
        "localRssFeeds",
        "rssBackgroundFetchEnabled",
        "presetSavePaths",
        "dashboardModuleOrder",
        "showTodayTransfer",
        "showTraffic",
        "showAggregation",
        "showServerStatus",
        "showStorageAudit",
        "showRecentTasks",
        "trackerAliases",
        "proDashboardBackgroundEnabled",
        "tmdbPosterDataEnabled",
        "customTMDBApiKey",
        "enableGlobalTaskAggregation",
        "appTheme",
        "appLanguage",
        "useHttpsDefault",
        "hideDataNodeName"
    ]

    private enum Keys {
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let lastSuccessfulSync = "iCloudSyncLastSuccessfulSync"
        static let lastErrorCode = "iCloudSyncLastErrorCode"
        static let isSyncing = "iCloudSyncIsSyncing"
    }

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let syncQueue = DispatchQueue(label: "com.seedpilot.icloud-sync", qos: .utility)

    // Canonical cloud keys -> local storage aliases (legacy/backward-compatible keys).
    private let localAliasesByCanonical: [String: [String]] = [
        "dashboardModuleOrder": [DashboardConfig.Keys.moduleOrder],
        "showTodayTransfer": [DashboardConfig.Keys.showTodayTransfer],
        "showTraffic": [DashboardConfig.Keys.showLiveTraffic],
        "showAggregation": [DashboardConfig.Keys.showGlobalAssets],
        "showServerStatus": [DashboardConfig.Keys.showServerStatus],
        "showStorageAudit": [DashboardConfig.Keys.showStorageAudit],
        "showRecentTasks": [DashboardConfig.Keys.showRecentFinished],
        "trackerAliases": ["trackerAliasMappings"],
        "tmdbPosterDataEnabled": ["showTMDBData", "tmdbPosterEnabled"],
        "appTheme": ["appearance"],
        "appLanguage": ["language"]
    ]

    private var hasStarted = false
    private var isApplyingCloudChanges = false
    private var isSyncing = false
    private var lastLocalSignatures: [String: Data] = [:]
    private var observers: [NSObjectProtocol] = []

    private init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
    }

    func currentStatus() -> SyncStatus {
        let syncing = defaults.bool(forKey: Keys.isSyncing)
        let lastSuccessfulSync = defaults.object(forKey: Keys.lastSuccessfulSync) as? Date
        let lastErrorCode = defaults.string(forKey: Keys.lastErrorCode).flatMap(ErrorCode.init(rawValue:))
        return SyncStatus(
            isEnabled: isSyncEnabled,
            isSyncing: syncing,
            lastSuccessfulSync: lastSuccessfulSync,
            lastErrorCode: lastErrorCode
        )
    }

    func start() {
        syncQueue.async {
            guard !self.hasStarted else { return }
            self.hasStarted = true
            self.registerObservers()
            self.refreshLocalSnapshot()
            self.postStatusDidChange()

            guard self.isSyncEnabled else { return }
            self.setSyncing(true)
            guard self.ensureICloudAvailable() else {
                self.setSyncing(false)
                return
            }
            _ = self.cloudStore.synchronize()
            self.pullFromCloud(keys: self.syncableKeys)
            self.markSuccess()
            self.setSyncing(false)
        }
    }

    func setSyncEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.iCloudSyncEnabled)
        start()

        syncQueue.async {
            self.refreshLocalSnapshot()
            guard enabled else {
                self.setSyncing(false)
                self.postStatusDidChange()
                return
            }

            self.setSyncing(true)
            guard self.ensureICloudAvailable() else {
                self.setSyncing(false)
                return
            }
            _ = self.cloudStore.synchronize()
            // Fresh install / re-install case:
            // if cloud already has sync data and this device has never synced before,
            // bootstrap from cloud first instead of overwriting it with local defaults.
            let hasPriorSuccessfulSync = self.defaults.object(forKey: Keys.lastSuccessfulSync) != nil
            let cloudHasExistingSyncData = self.syncableKeys.contains { self.cloudStore.object(forKey: $0) != nil }
            if !hasPriorSuccessfulSync && cloudHasExistingSyncData {
                self.pullFromCloud(keys: self.syncableKeys)
            } else {
                self.forcePushToCloudLocked()
            }
            self.markSuccess()
            self.setSyncing(false)
        }
    }

    func forcePushToCloud() {
        syncQueue.async {
            guard self.isSyncEnabled else { return }
            self.setSyncing(true)
            guard self.ensureICloudAvailable() else {
                self.setSyncing(false)
                return
            }
            self.forcePushToCloudLocked()
            self.markSuccess()
            self.setSyncing(false)
        }
    }

    func refreshFromCloudIfNeeded() {
        syncQueue.async {
            guard self.isSyncEnabled else { return }
            self.setSyncing(true)
            guard self.ensureICloudAvailable() else {
                self.setSyncing(false)
                return
            }
            _ = self.cloudStore.synchronize()
            self.pullFromCloud(keys: self.syncableKeys)
            self.markSuccess()
            self.setSyncing(false)
        }
    }

    private var isSyncEnabled: Bool {
        defaults.bool(forKey: Keys.iCloudSyncEnabled)
    }

    private func registerObservers() {
        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            if let sender = note.object as? UserDefaults, sender !== self.defaults {
                return
            }
            self.syncQueue.async {
                self.handleLocalDefaultsChanged()
            }
        }

        let cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            self.syncQueue.async {
                self.handleCloudStoreChanged(changedKeys: changedKeys, reason: reason)
            }
        }

        observers.append(defaultsObserver)
        observers.append(cloudObserver)
    }

    private func handleLocalDefaultsChanged() {
        guard isSyncEnabled, !isApplyingCloudChanges else { return }
        let changedKeys = detectChangedLocalKeys()
        guard !changedKeys.isEmpty else { return }
        setSyncing(true)
        guard ensureICloudAvailable() else {
            setSyncing(false)
            return
        }
        pushLocalKeysToCloud(changedKeys: changedKeys)
        markSuccess()
        setSyncing(false)
    }

    private func handleCloudStoreChanged(changedKeys: [String]?, reason: Int?) {
        guard isSyncEnabled else { return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            markFailure(.quotaExceeded)
            return
        }

        let validChangedKeys = (changedKeys ?? syncableKeys).filter { syncableKeys.contains($0) }
        guard !validChangedKeys.isEmpty else { return }
        setSyncing(true)
        guard ensureICloudAvailable() else {
            setSyncing(false)
            return
        }
        pullFromCloud(keys: validChangedKeys)
        markSuccess()
        setSyncing(false)
    }

    private func forcePushToCloudLocked() {
        pushLocalKeysToCloud(changedKeys: syncableKeys)
    }

    private func pullFromCloud(keys: [String]) {
        guard !keys.isEmpty else { return }
        isApplyingCloudChanges = true
        defer {
            isApplyingCloudChanges = false
            refreshLocalSnapshot()
        }

        for key in keys {
            guard syncableKeys.contains(key) else { continue }
            let cloudValue = cloudStore.object(forKey: key)
            let localValue = resolvedLocalValue(for: key)
            guard !valuesEqual(localValue, cloudValue) else { continue }
            applyCloudValueToLocal(cloudValue, canonicalKey: key)
            handlePostCloudApplyIfNeeded(canonicalKey: key, cloudValue: cloudValue)
        }
    }

    private func pushLocalKeysToCloud(changedKeys: [String]) {
        for key in changedKeys {
            guard syncableKeys.contains(key) else { continue }
            let localValue = resolvedLocalValue(for: key)
            let cloudValue = cloudStore.object(forKey: key)
            guard !valuesEqual(localValue, cloudValue) else { continue }

            if let localValue {
                cloudStore.set(localValue, forKey: key)
            } else {
                cloudStore.removeObject(forKey: key)
            }
        }
        cloudStore.synchronize()
    }

    private func detectChangedLocalKeys() -> [String] {
        var changed: [String] = []
        for key in syncableKeys {
            let value = resolvedLocalValue(for: key)
            let signature = makeValueSignature(value)
            let oldSignature = lastLocalSignatures[key]
            if oldSignature != signature {
                changed.append(key)
                if let signature {
                    lastLocalSignatures[key] = signature
                } else {
                    lastLocalSignatures.removeValue(forKey: key)
                }
            }
        }
        return changed
    }

    private func refreshLocalSnapshot() {
        var latest: [String: Data] = [:]
        for key in syncableKeys {
            if let signature = makeValueSignature(resolvedLocalValue(for: key)) {
                latest[key] = signature
            }
        }
        lastLocalSignatures = latest
    }

    private func resolvedLocalValue(for canonicalKey: String) -> Any? {
        for localKey in localKeys(for: canonicalKey) {
            if let value = defaults.object(forKey: localKey) {
                if let normalized = normalizeLocalValueForCloud(value, canonicalKey: canonicalKey) {
                    return normalized
                }
            }
        }
        return nil
    }

    private func applyCloudValueToLocal(_ cloudValue: Any?, canonicalKey: String) {
        for localKey in localKeys(for: canonicalKey) {
            let targetLocalValue = normalizeCloudValueForLocalStorage(
                cloudValue,
                canonicalKey: canonicalKey,
                localKey: localKey
            )
            let current = defaults.object(forKey: localKey)
            guard !valuesEqual(current, targetLocalValue) else { continue }
            if let targetLocalValue {
                defaults.set(targetLocalValue, forKey: localKey)
            } else {
                defaults.removeObject(forKey: localKey)
            }
        }
    }

    private func localKeys(for canonicalKey: String) -> [String] {
        var keys: [String] = [canonicalKey]
        let aliases = localAliasesByCanonical[canonicalKey] ?? []
        for alias in aliases where !keys.contains(alias) {
            keys.append(alias)
        }
        return keys
    }

    private func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        makeValueSignature(lhs) == makeValueSignature(rhs)
    }

    private func makeValueSignature(_ value: Any?) -> Data? {
        guard let value else { return nil }
        if let wrappedData = wrapDataSignature(value) {
            return wrappedData
        }

        let payload: [String: Any] = ["value": value]
        if PropertyListSerialization.propertyList(payload, isValidFor: .binary),
           let data = try? PropertyListSerialization.data(
                fromPropertyList: payload,
                format: .binary,
                options: 0
           ) {
            return data
        }

        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            return data
        }

        return String(describing: value).data(using: .utf8)
    }

    private func wrapDataSignature(_ value: Any) -> Data? {
        guard let data = value as? Data else { return nil }
        var wrapped = Data([0x44, 0x41, 0x54, 0x41]) // "DATA"
        wrapped.append(data)
        return wrapped
    }

    private func normalizeLocalValueForCloud(_ value: Any, canonicalKey: String) -> Any? {
        switch canonicalKey {
        case "presetSavePaths":
            if let raw = value as? String {
                return PresetSavePathsCodec.encode(PresetSavePathsCodec.decode(raw))
            }
            if let paths = value as? [String] {
                return PresetSavePathsCodec.encode(paths)
            }
            if let data = value as? Data {
                if let decoded = try? JSONDecoder().decode([String].self, from: data) {
                    return PresetSavePathsCodec.encode(decoded)
                }
                if let raw = String(data: data, encoding: .utf8) {
                    return PresetSavePathsCodec.encode(PresetSavePathsCodec.decode(raw))
                }
                return nil
            }
            return nil
        case "trackerAliases":
            if let data = value as? Data {
                return (try? JSONDecoder().decode([String: String].self, from: data)) ?? data
            }
            return value as? [String: String]
        case "dashboardModuleOrder":
            if let data = value as? Data {
                return (try? JSONDecoder().decode([String].self, from: data)) ?? data
            }
            return value as? [String]
        default:
            return value
        }
    }

    private func normalizeCloudValueForLocalStorage(
        _ cloudValue: Any?,
        canonicalKey: String,
        localKey: String
    ) -> Any? {
        switch canonicalKey {
        case "presetSavePaths":
            if let raw = cloudValue as? String {
                return PresetSavePathsCodec.encode(PresetSavePathsCodec.decode(raw))
            }
            if let paths = cloudValue as? [String] {
                return PresetSavePathsCodec.encode(paths)
            }
            if let data = cloudValue as? Data {
                if let decoded = try? JSONDecoder().decode([String].self, from: data) {
                    return PresetSavePathsCodec.encode(decoded)
                }
                if let raw = String(data: data, encoding: .utf8) {
                    return PresetSavePathsCodec.encode(PresetSavePathsCodec.decode(raw))
                }
                return nil
            }
            return nil
        case "trackerAliases":
            if localKey == "trackerAliasMappings" {
                if let data = cloudValue as? Data { return data }
                if let aliases = cloudValue as? [String: String] {
                    return try? JSONEncoder().encode(aliases)
                }
                return nil
            }
            return cloudValue
        case "dashboardModuleOrder":
            if localKey == DashboardConfig.Keys.moduleOrder {
                if let data = cloudValue as? Data { return data }
                if let order = cloudValue as? [String] {
                    return try? JSONEncoder().encode(order)
                }
                return nil
            }
            return cloudValue
        default:
            return cloudValue
        }
    }

    private func handlePostCloudApplyIfNeeded(canonicalKey: String, cloudValue: Any?) {
        if canonicalKey == "trackerAliases" {
            Task { @MainActor in
                TrackerAliasManager.shared.reloadFromStorageForExternalChange()
            }
        }

        if canonicalKey == "appLanguage" {
            let languageCode = (cloudValue as? String)
                ?? (defaults.string(forKey: "language"))
                ?? (defaults.string(forKey: "appLanguage"))
            guard let languageCode else { return }
            Task { @MainActor in
                LanguageManager.shared.setLanguage(code: languageCode)
            }
        }
    }

    private func ensureICloudAvailable() -> Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            markFailure(.accountUnavailable)
            return false
        }
        return true
    }

    private func setSyncing(_ syncing: Bool) {
        guard isSyncing != syncing else { return }
        isSyncing = syncing
        defaults.set(syncing, forKey: Keys.isSyncing)
        postStatusDidChange()
    }

    private func markSuccess() {
        defaults.set(Date(), forKey: Keys.lastSuccessfulSync)
        defaults.removeObject(forKey: Keys.lastErrorCode)
        postStatusDidChange()
    }

    private func markFailure(_ code: ErrorCode) {
        defaults.set(code.rawValue, forKey: Keys.lastErrorCode)
        postStatusDidChange()
    }

    private func postStatusDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iCloudSyncStatusDidChange, object: nil)
        }
    }
}
