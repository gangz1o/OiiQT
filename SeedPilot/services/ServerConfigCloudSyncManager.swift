import Foundation
import SwiftData

extension Notification.Name {
    static let serverConfigCloudSyncDidApply = Notification.Name("serverConfigCloudSyncDidApply")
}

@MainActor
final class ServerConfigCloudSyncManager {
    static let shared = ServerConfigCloudSyncManager()

    private enum Keys {
        static let cloudPayload = "serverConfigsPayloadV1"
        static let localMutationTime = "serverConfigsLocalMutationTime"
    }

    private enum Constants {
        static let payloadVersion = 2
    }

    private struct CloudServerPayload: Codable {
        let version: Int
        let updatedAt: Date
        let servers: [CloudServerRecord]
    }

    private struct CloudServerRecord: Codable, Hashable {
        let id: UUID
        let name: String
        let typeRawValue: String
        let address: String
        let port: Int
        let username: String
        let useHTTPS: Bool
        let allowInsecureSSL: Bool
        let rpcPath: String
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

    func handleLocalServerListChanged(_ servers: [ServerConfig]) {
        guard !isApplyingCloudChanges else { return }
        defaults.set(Date(), forKey: Keys.localMutationTime)
        pushLocalServersToCloudIfNeeded(servers)
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
        let localServers = fetchLocalServers(context: modelContext)
        let localRecords = makeRecords(from: localServers)
        let localSignature = signature(for: localRecords)
        let cloudPayload = readCloudPayload()

        guard let cloudPayload else {
            if !localServers.isEmpty {
                writeCloudPayload(servers: localRecords)
            }
            return
        }

        let cloudSignature = signature(for: cloudPayload.servers)

        if localSignature == cloudSignature {
            if cloudPayload.version < Constants.payloadVersion {
                writeCloudPayload(servers: localRecords)
            }
            return
        }

        if localServers.isEmpty {
            applyCloudPayloadIfNeeded()
            return
        }

        let localMutationTime = defaults.object(forKey: Keys.localMutationTime) as? Date
        let shouldPullCloud = (localMutationTime ?? .distantPast) < cloudPayload.updatedAt

        if shouldPullCloud {
            applyCloudPayloadIfNeeded()
        } else {
            writeCloudPayload(servers: localRecords)
        }
    }

    private func pushLocalServersToCloudIfNeeded(_ servers: [ServerConfig]) {
        guard isSyncEnabled else { return }
        guard ensureICloudAvailable() else { return }

        let localRecords = makeRecords(from: servers)
        let cloudRecords = readCloudPayload()?.servers ?? []
        guard signature(for: localRecords) != signature(for: cloudRecords) else { return }

        writeCloudPayload(servers: localRecords)
    }

    private func applyCloudPayloadIfNeeded() {
        guard let modelContext else { return }
        guard let payload = readCloudPayload() else { return }

        let localServers = fetchLocalServers(context: modelContext)
        let localRecords = makeRecords(from: localServers)
        guard signature(for: localRecords) != signature(for: payload.servers) else { return }

        isApplyingCloudChanges = true
        defer { isApplyingCloudChanges = false }

        applyRecords(payload.servers, to: modelContext)
        defaults.set(payload.updatedAt, forKey: Keys.localMutationTime)
        if payload.version < Constants.payloadVersion {
            writeCloudPayload(servers: payload.servers)
        }

        NotificationCenter.default.post(name: .serverConfigCloudSyncDidApply, object: nil)
    }

    private func fetchLocalServers(context: ModelContext) -> [ServerConfig] {
        let descriptor = FetchDescriptor<ServerConfig>()
        let servers = (try? context.fetch(descriptor)) ?? []
        return servers.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func makeRecords(from servers: [ServerConfig]) -> [CloudServerRecord] {
        servers
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { server in
                CloudServerRecord(
                    id: server.id,
                    name: server.name,
                    typeRawValue: server.type.rawValue,
                    address: server.address,
                    port: server.port,
                    username: server.username,
                    useHTTPS: server.useHTTPS,
                    allowInsecureSSL: server.allowInsecureSSL,
                    rpcPath: server.rpcPath
                )
            }
    }

    private func applyRecords(_ records: [CloudServerRecord], to context: ModelContext) {
        let existingServers = fetchLocalServers(context: context)
        var existingByID = Dictionary(uniqueKeysWithValues: existingServers.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))

        for record in records {
            if let server = existingByID.removeValue(forKey: record.id) {
                update(server, from: record)
            } else {
                context.insert(makeServerConfig(from: record))
            }
        }

        for stale in existingByID.values where !incomingIDs.contains(stale.id) {
            stale.deleteResolvedPassword()
            context.delete(stale)
        }

        try? context.save()
    }

    private func update(_ server: ServerConfig, from record: CloudServerRecord) {
        server.name = record.name
        server.type = ServerType(rawValue: record.typeRawValue) ?? .qBittorrent
        server.address = record.address
        server.port = record.port
        server.username = record.username
        server.useHTTPS = record.useHTTPS
        server.allowInsecureSSL = record.allowInsecureSSL
        server.rpcPath = record.rpcPath
    }

    private func makeServerConfig(from record: CloudServerRecord) -> ServerConfig {
        let config = ServerConfig(
            name: record.name,
            type: ServerType(rawValue: record.typeRawValue) ?? .qBittorrent,
            address: record.address,
            port: record.port,
            username: record.username,
            password: "",
            useHTTPS: record.useHTTPS,
            allowInsecureSSL: record.allowInsecureSSL,
            rpcPath: record.rpcPath
        )
        config.id = record.id
        return config
    }

    private func readCloudPayload() -> CloudServerPayload? {
        if let data = cloudStore.data(forKey: Keys.cloudPayload) {
            return try? Self.decoder.decode(CloudServerPayload.self, from: data)
        }

        if let dict = cloudStore.dictionary(forKey: Keys.cloudPayload),
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let payload = try? Self.decoder.decode(CloudServerPayload.self, from: data) {
            return payload
        }

        return nil
    }

    private func writeCloudPayload(servers: [CloudServerRecord]) {
        let payload = CloudServerPayload(version: Constants.payloadVersion, updatedAt: Date(), servers: servers)
        guard let data = try? Self.encoder.encode(payload) else { return }
        cloudStore.set(data, forKey: Keys.cloudPayload)
        cloudStore.synchronize()
    }

    private func signature(for records: [CloudServerRecord]) -> Data? {
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
