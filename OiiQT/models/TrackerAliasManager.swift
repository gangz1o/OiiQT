import Foundation
import Combine

struct TrackerAliasRule: Identifiable, Hashable {
    let originalDomain: String
    let alias: String

    var id: String { originalDomain }
}

@MainActor
final class TrackerAliasManager: ObservableObject {
    static let shared = TrackerAliasManager()

    private let storageKey = "trackerAliasMappings"
    private let envelopeKey = "trackerAliasesSyncEnvelope"
    private let defaults: UserDefaults

    @Published private(set) var aliasMap: [String: String] = [:]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFromStorage()
    }

    var rules: [TrackerAliasRule] {
        aliasMap
            .map { TrackerAliasRule(originalDomain: $0.key, alias: $0.value) }
            .sorted { $0.originalDomain.localizedCaseInsensitiveCompare($1.originalDomain) == .orderedAscending }
    }

    func getAlias(for tracker: String) -> String {

        let normalized = normalizeTrackerDomain(tracker)
        guard !normalized.isEmpty else { return tracker }
        let alias = aliasMap[normalized]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return alias.isEmpty ? tracker : alias
    }

    func upsert(originalDomain: String, alias: String) {
        let normalizedDomain = normalizeTrackerDomain(originalDomain)
        let sanitizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty, !sanitizedAlias.isEmpty else { return }

        aliasMap[normalizedDomain] = sanitizedAlias
        persist()
    }

    func remove(originalDomain: String) {
        let normalizedDomain = normalizeTrackerDomain(originalDomain)
        guard !normalizedDomain.isEmpty else { return }
        aliasMap.removeValue(forKey: normalizedDomain)
        persist()
    }

    func remove(at offsets: IndexSet) {
        let rows = rules
        for index in offsets {
            guard rows.indices.contains(index) else { continue }
            aliasMap.removeValue(forKey: rows[index].originalDomain)
        }
        persist()
    }

    func reloadFromStorageForExternalChange() {
        loadFromStorage()
    }

    func normalizeTrackerDomain(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }

        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }

        value = value.lowercased()

        if !value.hasPrefix("["),
           let colon = value.lastIndex(of: ":"),
           colon != value.startIndex {
            let hostPart = String(value[..<colon])
            let portPart = String(value[value.index(after: colon)...])
            if Int(portPart) != nil {
                value = hostPart
            }
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFromStorage() {
        // Prefer loading from the envelope key (has timestamp metadata)
        if let envelopeData = defaults.data(forKey: envelopeKey),
           let envelope = try? JSONDecoder().decode(SyncableData<[String: String]>.self, from: envelopeData) {
            aliasMap = normalize(map: envelope.payload)
            return
        }

        // Fallback: legacy raw data key (no timestamp; written by older app versions)
        guard let data = defaults.data(forKey: storageKey) else {
            aliasMap = [:]
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            aliasMap = [:]
            return
        }

        aliasMap = normalize(map: decoded)
    }

    private func normalize(map: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (domain, alias) in map {
            let key = normalizeTrackerDomain(domain)
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            normalized[key] = value
        }
        return normalized
    }

    private func persist() {
        let now = Date().timeIntervalSince1970

        if aliasMap.isEmpty {
            defaults.removeObject(forKey: storageKey)
            // Keep envelope with empty payload + updated timestamp so the merge guard
            // knows this device intentionally cleared the aliases.
            let emptyEnvelope = SyncableData(payload: [String: String](), lastUpdated: now)
            if let data = try? JSONEncoder().encode(emptyEnvelope) {
                defaults.set(data, forKey: envelopeKey)
            }
            return
        }

        // 1. Persist raw payload (for legacy readers & trackerAliasMappings key)
        if let encoded = try? JSONEncoder().encode(aliasMap) {
            defaults.set(encoded, forKey: storageKey)
        }

        // 2. Persist envelope with timestamp (used by iCloudSyncManager merge guard)
        let envelope = SyncableData(payload: aliasMap, lastUpdated: now)
        if let envelopeData = try? JSONEncoder().encode(envelope) {
            defaults.set(envelopeData, forKey: envelopeKey)
        }
    }
}
