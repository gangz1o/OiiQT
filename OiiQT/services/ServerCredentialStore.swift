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

    func setPassword(_ password: String, for serverID: UUID) {
        if password.isEmpty {
            deletePassword(for: serverID)
            return
        }

        let account = account(for: serverID)
        let data = Data(password.utf8)

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
                setPassword(server.password, for: server.id)
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

