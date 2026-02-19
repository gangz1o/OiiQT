//
//  AddServerView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

struct EditServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var serverToEdit: ServerConfig? // Optional server to edit

    @State private var name = ""
    @State private var type: ServerType = .qBittorrent
    @State private var address = ""
    @State private var port = "8080"
    @State private var username = ""
    @State private var password = ""
    @State private var isHttps = false
    @State private var allowInsecureSSL = false
    @State private var rpcPath = "/transmission/rpc"
    @State private var isPasswordVisible = false

    // Test Connection State
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var isFormValid: Bool {
        !name.isEmpty && !address.isEmpty && !port.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(LanguageManager.shared.localized("Type"), selection: $type) {
                        ForEach(ServerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(LanguageManager.shared.localized("Server Type"))
                }

                Section {
                    HStack {
                        Image(systemName: "tag.fill")
                        TextField(LanguageManager.shared.localized("Name (e.g. Home NAS)"), text: $name)
                    }

                    HStack {
                        Image(systemName: "network")
                        TextField(LanguageManager.shared.localized("IP Address or Domain"), text: $address)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Image(systemName: "number")
                        TextField(LanguageManager.shared.localized("Port"), text: $port)
                            .keyboardType(.numberPad)
                    }

                    if type == .transmission {
                        HStack {
                            Image(systemName: "folder.fill")
                            TextField(LanguageManager.shared.localized("RPC Path"), text: $rpcPath)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Server Information"))
                } footer: {
                    Text(LanguageManager.shared.localized("No need to enter http:// or https://, the system handles it automatically."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.blue) // Tint icons

                // MARK: - SSL Settings
                Section {
                    Toggle(isOn: $isHttps.animation()) {
                        HStack(spacing: 12) {
                            AppleStyleIcon(backgroundColor: .blue, systemName: "lock.fill")
                            Text(LanguageManager.shared.localized("Use HTTPS"))
                        }
                    }

                    if isHttps {
                        Toggle(isOn: $allowInsecureSSL.animation()) {
                            HStack(spacing: 12) {
                                AppleStyleIcon(backgroundColor: .orange, systemName: "shield.slash")
                                Text(LanguageManager.shared.localized("Ignore SSL Certificate Errors"))
                            }
                        }
                    }
                } footer: {
                    if isHttps {
                        Text(LanguageManager.shared.localized("Allow connections to self-signed or invalid SSL certificates."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        TextField(LanguageManager.shared.localized("Username"), text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.blue)

                        if isPasswordVisible {
                            TextField(LanguageManager.shared.localized("Password"), text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(LanguageManager.shared.localized("Password"), text: $password)
                        }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Authentication"))
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .padding(.horizontal)
                        } else {
                            HStack {
                                Spacer()
                                Text(LanguageManager.shared.localized("Test Connection"))
                                Spacer()
                            }
                        }
                    }
                    .disabled(isTesting || !isFormValid)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.icon)
                                .foregroundStyle(result.color)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(result.color)
                        }
                    }
                } footer: {
                    Text(LanguageManager.shared.localized("qBittorrent v4.1.0+ or Transmission v2.9.4+ is recommended for full feature support."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle(serverToEdit == nil ? LanguageManager.shared.localized("Add Server") : LanguageManager.shared.localized("Edit Server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Save")) {
                        saveServer()
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                if let server = serverToEdit {
                    name = server.name
                    type = server.type
                    isHttps = resolvedHTTPSFlag(from: server)
                    address = sanitizeAddressInput(server.address)
                    port = String(server.port)
                    username = server.username
                    password = server.password
                    allowInsecureSSL = server.allowInsecureSSL
                    rpcPath = server.rpcPath
                }
            }
            .onChange(of: address) { _, newValue in
                handleAddressChanged(newValue)
            }
            .onChange(of: isHttps) { _, enabled in
                if !enabled {
                    allowInsecureSSL = false
                }
            }
        }
    }

    private func saveServer() {
        let formattedAddress = sanitizeAddressInput(address)

        if let server = serverToEdit {
            // Update
            server.name = name.trimmingCharacters(in: .whitespaces)
            server.type = type
            server.address = formattedAddress
            server.port = Int(port) ?? 8080
            server.username = username.trimmingCharacters(in: .whitespaces)
            server.password = password
            server.useHTTPS = isHttps
            server.allowInsecureSSL = allowInsecureSSL
            server.rpcPath = rpcPath.trimmingCharacters(in: .whitespaces)
        } else {
            // Insert
            let config = ServerConfig(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                useHTTPS: isHttps,
                allowInsecureSSL: allowInsecureSSL,
                rpcPath: rpcPath.trimmingCharacters(in: .whitespaces)
            )
            modelContext.insert(config)
        }
        dismiss()
    }

    private func testConnection() {
        guard isFormValid else { return }
        isTesting = true
        testResult = nil

        Task {
            // Construct temp config
            let formattedAddress = sanitizeAddressInput(address)

            let tempConfig = ServerConfig(
                name: "Test",
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                useHTTPS: isHttps,
                allowInsecureSSL: allowInsecureSSL,
                rpcPath: rpcPath.trimmingCharacters(in: .whitespaces)
            )

            let client: TorrentClient = (type == .qBittorrent) ?
                QBittorrentClient(config: tempConfig) :
                TransmissionClient(config: tempConfig)

            do {
                try await client.login()
                let version = try await client.checkConnection()
                testResult = .success(
                    String(format: LanguageManager.shared.localized("Connection succeeded: %@ (v%@)"), type.rawValue, version)
                )
            } catch {
                if let urlError = error as? URLError,
                   urlError.code == .serverCertificateUntrusted || urlError.code == .secureConnectionFailed,
                   !allowInsecureSSL {
                    testResult = .failure(
                        LanguageManager.shared.localized("SSL verification failed. If you are using a self-signed certificate, enable \"Ignore SSL Certificate Errors\" and try again.")
                    )
                } else {
                    testResult = .failure(
                        String(format: LanguageManager.shared.localized("Connection failed: %@"), error.localizedDescription)
                    )
                }
            }
            isTesting = false
        }
    }

    private func handleAddressChanged(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("https://") {
            isHttps = true
        } else if lower.hasPrefix("http://") {
            isHttps = false
        }

        let sanitized = sanitizeAddressInput(trimmed)
        if sanitized != rawValue {
            address = sanitized
        }
    }

    private func sanitizeAddressInput(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        if lower.hasPrefix("https://") {
            if let url = URL(string: value), let host = url.host, !host.isEmpty {
                return host
            }
            value = String(value.dropFirst(8))
        } else if lower.hasPrefix("http://") {
            if let url = URL(string: value), let host = url.host, !host.isEmpty {
                return host
            }
            value = String(value.dropFirst(7))
        }

        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }

        if !value.hasPrefix("["),
           let colon = value.lastIndex(of: ":"),
           colon != value.startIndex {
            let hostPart = String(value[..<colon])
            let portPart = String(value[value.index(after: colon)...])
            if Int(portPart) != nil, !hostPart.isEmpty {
                value = hostPart
            }
        }

        return value
    }

    private func resolvedHTTPSFlag(from server: ServerConfig) -> Bool {
        let lower = server.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("https://") { return true }
        if lower.hasPrefix("http://") { return false }
        return server.useHTTPS
    }
}

private struct AppleStyleIcon: View {
    let backgroundColor: Color
    let systemName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [backgroundColor.opacity(0.96), backgroundColor.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

extension EditServerView.TestResult {
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        }
    }

    var message: String {
        switch self {
        case .success(let msg): return msg
        case .failure(let msg): return msg
        }
    }
}

#Preview {
    EditServerView()
        .modelContainer(for: ServerConfig.self, inMemory: true)
}
