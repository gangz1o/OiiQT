import Foundation
import Security
import SwiftData

final class ServerCredentialStore {
    static let shared = ServerCredentialStore()

    private let service: String

    private init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.gangz1o.oiiqt.app") {
        self.service = "\(bundleID).server-password"
    }

    func password(for serverID: UUID) -> String? {
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

    func setPassword(_ password: String, for serverID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        if password.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            return
        }

        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(password.utf8)
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrSynchronizable as String] = kCFBooleanTrue
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func deletePassword(for serverID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    @MainActor
    func migrateLegacyPasswords(in context: ModelContext) {
        let descriptor = FetchDescriptor<ServerConfig>()
        guard let servers = try? context.fetch(descriptor), !servers.isEmpty else { return }

        var didChange = false
        for server in servers {
            guard !server.password.isEmpty else { continue }

            if (password(for: server.id) ?? "").isEmpty {
                do {
                    try setPassword(server.password, for: server.id)
                } catch {
                    // Keep the legacy password until Keychain has accepted it.
                    continue
                }
            }

            server.password = ""
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }

    private func account(for serverID: UUID) -> String {
        "server.\(serverID.uuidString.lowercased())"
    }
}

