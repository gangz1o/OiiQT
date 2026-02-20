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
        guard let data = defaults.data(forKey: storageKey) else {
            aliasMap = [:]
            return
        }

        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            aliasMap = [:]
            return
        }

        var normalized: [String: String] = [:]
        for (domain, alias) in decoded {
            let key = normalizeTrackerDomain(domain)
            let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            normalized[key] = value
        }
        aliasMap = normalized
    }

    private func persist() {
        if aliasMap.isEmpty {
            defaults.removeObject(forKey: storageKey)
            return
        }

        guard let encoded = try? JSONEncoder().encode(aliasMap) else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}
