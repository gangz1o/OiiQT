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
                Section("服务器类型") {
                    Picker("类型", selection: $type) {
                        ForEach(ServerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("服务器信息") {
                    HStack {
                        Image(systemName: "tag.fill")
                        TextField("名称 (例如: 家里的 NAS)", text: $name)
                    }

                    HStack {
                        Image(systemName: "network")
                        TextField("IP 地址或域名", text: $address)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Image(systemName: "number")
                        TextField("端口", text: $port)
                            .keyboardType(.numberPad)
                    }
                }
                .foregroundStyle(.blue) // Tint icons

                // MARK: - SSL Settings
                if address.lowercased().hasPrefix("https") || address.lowercased().hasPrefix("http") == false {
                    Section {
                        Toggle(isOn: $allowInsecureSSL.animation()) {
                            Label {
                                Text("忽略 SSL 证书错误")
                            } icon: {
                                Image(systemName: "shield.slash")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } footer: {
                        Text("允许连接自签名或无效的 SSL 证书。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("认证信息") {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.blue)

                        if isPasswordVisible {
                            TextField("密码", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("密码", text: $password)
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
                                Text("测试连接")
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
                }
            }
            .navigationTitle(serverToEdit == nil ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                }
            }
        }
    }

    private func saveServer() {
        // 处理地址前缀
        let formattedAddress = address.trimmingCharacters(in: .whitespaces)
        // Remove existing protocol if user typed it again awkwardly or just clean up
        // Keep the protocol if user typed it
        // if formattedAddress.hasPrefix("http://") { ... }

        // We will store raw address without protocol usually, or keep consistent?
        // AppStateManager/Client logic adds http:// if missing.
        // Let's store pure IP/Domain to be clean, or keep logical.
        // Current Client logic: checks prefix.
        // Let's just trim whitespace.

        if let server = serverToEdit {
            // Update
            server.name = name.trimmingCharacters(in: .whitespaces)
            server.type = type
            server.address = formattedAddress
            server.port = Int(port) ?? 8080
            server.username = username.trimmingCharacters(in: .whitespaces)
            server.password = password
            server.allowInsecureSSL = allowInsecureSSL
        } else {
            // Insert
            let config = ServerConfig(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                allowInsecureSSL: allowInsecureSSL
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
            // Keep protocol
            // if formattedAddress.hasPrefix("http://") { ... }

            let tempConfig = ServerConfig(
                name: "Test",
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                allowInsecureSSL: allowInsecureSSL
            )

            let client = QBittorrentClient(config: tempConfig)

            do {
                try await client.login()
                let version = try await client.checkConnection()
                testResult = .success("连接成功 (v\(version))")
            } catch {
                if let urlError = error as? URLError,
                   urlError.code == .serverCertificateUntrusted || urlError.code == .secureConnectionFailed,
                   !allowInsecureSSL {
                    testResult = .failure("SSL 验证失败。如果您使用的是自签名证书，请开启“忽略 SSL 错误”后重试。")
                } else {
                    testResult = .failure("连接失败: \(error.localizedDescription)")
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
