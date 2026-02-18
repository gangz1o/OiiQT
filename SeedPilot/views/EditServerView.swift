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
                Section(LanguageManager.shared.localized("Server Type")) {
                    Picker(LanguageManager.shared.localized("Type"), selection: $type) {
                        ForEach(ServerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(LanguageManager.shared.localized("Server Information")) {
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
                }
                .foregroundStyle(.blue) // Tint icons

                // MARK: - SSL Settings
                if address.lowercased().hasPrefix("https") || address.lowercased().hasPrefix("http") == false {
                    Section {
                        Toggle(isOn: $allowInsecureSSL.animation()) {
                            Label {
                                Text(LanguageManager.shared.localized("Ignore SSL Certificate Errors"))
                            } icon: {
                                Image(systemName: "shield.slash")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } footer: {
                        Text(LanguageManager.shared.localized("Allow connections to self-signed or invalid SSL certificates."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(LanguageManager.shared.localized("Authentication")) {
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
                    address = server.address
                    port = String(server.port)
                    username = server.username
                    password = server.password
                    allowInsecureSSL = server.allowInsecureSSL
                    rpcPath = server.rpcPath
                }
            }
        }
    }

    private func saveServer() {
        // 处理地址前缀
        let formattedAddress = address.trimmingCharacters(in: .whitespaces)

        if let server = serverToEdit {
            // Update
            server.name = name.trimmingCharacters(in: .whitespaces)
            server.type = type
            server.address = formattedAddress
            server.port = Int(port) ?? 8080
            server.username = username.trimmingCharacters(in: .whitespaces)
            server.password = password
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
            let formattedAddress = address.trimmingCharacters(in: .whitespaces)

            let tempConfig = ServerConfig(
                name: "Test",
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
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
