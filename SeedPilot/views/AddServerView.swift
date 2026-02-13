//
//  AddServerView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

struct AddServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var serverToEdit: ServerConfig? // Optional server to edit
    
    @State private var name = ""
    @State private var type: ServerType = .qBittorrent
    @State private var address = ""
    @State private var port = "8080"
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    
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
                }
            }
        }
    }
    
    private func saveServer() {
        // 处理地址前缀
        var formattedAddress = address.trimmingCharacters(in: .whitespaces)
        // Remove existing protocol if user typed it again awkwardly or just clean up
        if formattedAddress.hasPrefix("http://") {
             formattedAddress = String(formattedAddress.dropFirst(7))
        } else if formattedAddress.hasPrefix("https://") {
             formattedAddress = String(formattedAddress.dropFirst(8))
        }
        
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
        } else {
            // Insert
            let config = ServerConfig(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                address: formattedAddress,
                port: Int(port) ?? 8080,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            modelContext.insert(config)
        }
        dismiss()
    }
}

#Preview {
    AddServerView()
        .modelContainer(for: ServerConfig.self, inMemory: true)
}
