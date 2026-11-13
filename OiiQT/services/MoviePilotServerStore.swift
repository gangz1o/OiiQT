import Foundation
import Observation
import Security
import Combine

final class MoviePilotTokenStore {
    static let shared = MoviePilotTokenStore()

    private let service: String

    private init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.gangz1o.oiiqt.app") {
        self.service = "\(bundleID).moviepilot-token"
    }

    func token(for serverID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setToken(_ token: String, for serverID: UUID) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            deleteToken(for: serverID)
            return
        }

        let account = account(for: serverID)
        let data = Data(trimmedToken.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func deleteToken(for serverID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(for serverID: UUID) -> String {
        "moviepilot.\(serverID.uuidString.lowercased())"
    }
}

@MainActor
@Observable
final class MoviePilotServerStore {
    static let shared = MoviePilotServerStore()

    @ObservationIgnored
    private let configuredStateSubject: CurrentValueSubject<Bool, Never>

    private let defaults: UserDefaults
    private let tokenStore: MoviePilotTokenStore
    private let storageKey = "moviePilot.server.configurations"
    private let activeServerIDKey = "moviePilot.server.active-id"

    private(set) var servers: [MoviePilotServerConfiguration] = []
    private(set) var isMoviePilotConfigured = false
    private(set) var activeServerID: UUID?

    var configuredStatePublisher: AnyPublisher<Bool, Never> {
        configuredStateSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var activeServerName: String? {
        activeServerContext?.serverName
    }

    var activeServerContext: MoviePilotServerRequestContext? {
        guard let activeServerID else { return nil }
        return makeRequestContext(for: activeServerID)
    }

    var availableServerContexts: [MoviePilotServerRequestContext] {
        servers.compactMap(makeRequestContext(for:))
    }

    var hasMultipleAvailableServers: Bool {
        availableServerContexts.count > 1
    }

    init(
        defaults: UserDefaults = .standard,
        tokenStore: MoviePilotTokenStore? = nil
    ) {
        self.configuredStateSubject = CurrentValueSubject(false)
        self.defaults = defaults
        self.tokenStore = tokenStore ?? MoviePilotTokenStore.shared
        self.activeServerID = Self.loadPersistedActiveServerID(from: defaults, key: activeServerIDKey)
        load()
    }

    func token(for serverID: UUID) -> String? {
        tokenStore.token(for: serverID)
    }

    func upsert(id: UUID?, name: String, baseURLString: String, typedToken: String?) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = MoviePilotURLNormalizer.normalize(baseURLString) ?? baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = id ?? UUID()

        if let index = servers.firstIndex(where: { $0.id == targetID }) {
            servers[index].name = normalizedName
            servers[index].baseURLString = normalizedURL
        } else {
            servers.append(
                MoviePilotServerConfiguration(
                    id: targetID,
                    name: normalizedName,
                    baseURLString: normalizedURL
                )
            )
        }

        if let typedToken {
            tokenStore.setToken(typedToken, for: targetID)
        }

        sortServers()
        persist()
    }

    func delete(_ server: MoviePilotServerConfiguration) {
        servers.removeAll { $0.id == server.id }
        tokenStore.deleteToken(for: server.id)
        persist()
    }

    func setActiveServer(_ serverID: UUID) {
        guard availableServerContexts.contains(where: { $0.serverID == serverID }) else {
            return
        }
        guard activeServerID != serverID else { return }
        activeServerID = serverID
        persistActiveServerSelection()
    }

    func reload() {
        load()
    }

    private func load() {
        activeServerID = Self.loadPersistedActiveServerID(from: defaults, key: activeServerIDKey)

        guard let data = defaults.data(forKey: storageKey) else {
            servers = []
            updateConfiguredState()
            return
        }

        do {
            servers = try JSONDecoder().decode([MoviePilotServerConfiguration].self, from: data)
            sortServers()
        } catch {
            servers = []
        }

        updateConfiguredState()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(servers)
            defaults.set(data, forKey: storageKey)
        } catch {
            defaults.removeObject(forKey: storageKey)
        }

        updateConfiguredState()
    }

    private func sortServers() {
        servers.sort { lhs, rhs in
            let ordered = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if ordered == .orderedSame {
                return lhs.baseURLString.localizedCaseInsensitiveCompare(rhs.baseURLString) == .orderedAscending
            }
            return ordered == .orderedAscending
        }
    }

    private func updateConfiguredState() {
        let availableContexts = availableServerContexts
        let nextValue = !availableContexts.isEmpty
        let nextActiveServerID: UUID?

        if let activeServerID,
           availableContexts.contains(where: { $0.serverID == activeServerID }) {
            nextActiveServerID = activeServerID
        } else {
            nextActiveServerID = availableContexts.first?.serverID
        }

        if activeServerID != nextActiveServerID {
            activeServerID = nextActiveServerID
            persistActiveServerSelection()
        }

        isMoviePilotConfigured = nextValue
        configuredStateSubject.send(nextValue)
    }

    private func makeRequestContext(for server: MoviePilotServerConfiguration) -> MoviePilotServerRequestContext? {
        guard let normalizedBaseURL = MoviePilotURLNormalizer.normalize(server.baseURLString) else {
            return nil
        }

        let trimmedToken = tokenStore.token(for: server.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty else {
            return nil
        }

        return MoviePilotServerRequestContext(
            serverID: server.id,
            serverName: server.name,
            baseURLString: normalizedBaseURL,
            token: trimmedToken
        )
    }

    private func makeRequestContext(for serverID: UUID) -> MoviePilotServerRequestContext? {
        guard let server = servers.first(where: { $0.id == serverID }) else {
            return nil
        }
        return makeRequestContext(for: server)
    }

    private func persistActiveServerSelection() {
        if let activeServerID {
            defaults.set(activeServerID.uuidString, forKey: activeServerIDKey)
        } else {
            defaults.removeObject(forKey: activeServerIDKey)
        }
    }

    private static func loadPersistedActiveServerID(from defaults: UserDefaults, key: String) -> UUID? {
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }
}
