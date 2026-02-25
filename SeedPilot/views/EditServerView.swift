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
    @State private var showingDeleteConfirmation = false

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

    private var pathRowTitle: String {
        if type == .qBittorrent {
            return "API \(LanguageManager.shared.localized("Path"))"
        }
        return LanguageManager.shared.localized("RPC Path")
    }

    private var pathPlaceholder: String {
        defaultPath(for: type)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $type) {
                        ForEach(ServerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    } label: {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Type"),
                            iconName: "externaldrive.connected.to.line.below",
                            color: .purple
                        )
                    }
                    .tint(.primary)

                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Name"),
                            iconName: "tag.fill",
                            color: .purple
                        )

                        TextField(LanguageManager.shared.localized("Name (e.g. Home NAS)"), text: $name)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Server Information"))
                }

                Section {
                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("IP Address or Domain"),
                            iconName: "network",
                            color: .blue
                        )

                        TextField(LanguageManager.shared.localized("IP Address or Domain"), text: $address)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Port"),
                            iconName: "number.square.fill",
                            color: .blue
                        )

                        TextField(LanguageManager.shared.localized("Port"), text: $port)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: pathRowTitle,
                            iconName: "folder.fill",
                            color: .blue
                        )

                        TextField(pathPlaceholder, text: $rpcPath)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Toggle(isOn: $isHttps.animation()) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Use HTTPS"),
                            iconName: "lock.shield.fill",
                            color: .green
                        )
                    }

                    if isHttps {
                        Toggle(isOn: $allowInsecureSSL.animation()) {
                            settingsRowLabel(
                                title: LanguageManager.shared.localized("Ignore SSL Certificate Errors"),
                                iconName: "shield.slash.fill",
                                color: .orange
                            )
                        }
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Server Settings"))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.shared.localized("No need to enter http:// or https://, the system handles it automatically."))
                        if isHttps {
                            Text(LanguageManager.shared.localized("Allow connections to self-signed or invalid SSL certificates."))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section {
                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Username"),
                            iconName: "person.fill",
                            color: .orange
                        )

                        TextField(LanguageManager.shared.localized("Username"), text: $username)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack(spacing: 12) {
                        settingsRowLabel(
                            title: LanguageManager.shared.localized("Password"),
                            iconName: "key.fill",
                            color: .orange
                        )

                        Group {
                            if isPasswordVisible {
                                TextField(LanguageManager.shared.localized("Password"), text: $password)
                            } else {
                                SecureField(LanguageManager.shared.localized("Password"), text: $password)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Authentication"))
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        centeredActionRowLabel {
                            if isTesting {
                                ProgressView()
                            } else {
                                Text(LanguageManager.shared.localized("Test Connection"))
                            }
                        }
                    }
                    .disabled(isTesting || !isFormValid)
                    .foregroundStyle(.blue)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                        dimensions.width
                    }

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

                if serverToEdit != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            centeredActionRowLabel {
                                Text(LanguageManager.shared.localized("Delete Server"))
                            }
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                            dimensions.width
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
                    password = server.resolvedPassword
                    allowInsecureSSL = server.allowInsecureSSL
                    rpcPath = defaultPathForEditing(server)
                } else {
                    rpcPath = defaultPath(for: type)
                }
            }
            .onChange(of: address) { _, newValue in
                handleAddressChanged(newValue)
            }
            .onChange(of: type) { oldValue, newValue in
                let trimmed = rpcPath.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.isEmpty ? "" : normalizePathString(trimmed)
                let oldDefault = defaultPath(for: oldValue)

                if normalized.isEmpty || normalized == oldDefault || normalized == "/transmission/rpc" || normalized == "/api/v2" {
                    rpcPath = defaultPath(for: newValue)
                }
            }
            .onChange(of: isHttps) { _, enabled in
                if !enabled {
                    allowInsecureSSL = false
                }
            }
            .alert(LanguageManager.shared.localized("Delete Server"), isPresented: $showingDeleteConfirmation) {
                Button(LanguageManager.shared.localized("Delete"), role: .destructive) {
                    if let server = serverToEdit {
                        server.deleteResolvedPassword()
                        modelContext.delete(server)
                    }
                    dismiss()
                }
                Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func settingsRowLabel(title: String, iconName: String, color: Color) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            SettingsIcon(iconName: iconName, color: color)
        }
    }

    @ViewBuilder
    private func centeredActionRowLabel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
        .contentShape(Rectangle())
    }

    private func saveServer() {
        let formattedAddress = sanitizeAddressInput(address)
        let normalizedPath = effectivePathForCurrentType()

        if let server = serverToEdit {
            // Update
            server.name = name.trimmingCharacters(in: .whitespaces)
            server.type = type
            server.address = formattedAddress
            server.port = Int(port) ?? 8080
            server.username = username.trimmingCharacters(in: .whitespaces)
            server.setResolvedPassword(password)
            server.useHTTPS = isHttps
            server.allowInsecureSSL = allowInsecureSSL
            server.rpcPath = normalizedPath
        } else {
            // Insert
            let config = ServerConfig(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: "",
                useHTTPS: isHttps,
                allowInsecureSSL: allowInsecureSSL,
                rpcPath: normalizedPath
            )
            config.setResolvedPassword(password)
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
                rpcPath: effectivePathForCurrentType()
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

    private func defaultPath(for type: ServerType) -> String {
        switch type {
        case .qBittorrent:
            return "/api/v2"
        case .transmission:
            return "/transmission/rpc"
        }
    }

    private func normalizePathString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func effectivePathForCurrentType() -> String {
        let normalized = normalizePathString(rpcPath)
        if normalized.isEmpty { return defaultPath(for: type) }
        if type == .qBittorrent && normalized == "/transmission/rpc" { return "/api/v2" }
        return normalized
    }

    private func defaultPathForEditing(_ server: ServerConfig) -> String {
        let normalized = normalizePathString(server.rpcPath)
        if normalized.isEmpty { return defaultPath(for: server.type) }
        if server.type == .qBittorrent && normalized == "/transmission/rpc" {
            return "/api/v2"
        }
        return normalized
    }
}

struct SettingsIcon: View {
    let iconName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)

            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 28, height: 28)
    }
}

struct AppleStyleIcon: View {
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
