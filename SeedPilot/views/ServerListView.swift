//
//  ServerListView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appStateManager
    @Query private var servers: [ServerConfig]
    
    @State private var showingAddServer = false
    @State private var editingServer: ServerConfig?
    
    var body: some View {
        List {
            if servers.isEmpty {
                ContentUnavailableView(
                    "暂无服务器",
                    systemImage: "server.rack",
                    description: Text("点击右上角 + 添加您的下载服务器")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(servers) { server in
                    ServerCardRow(server: server)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingServer = server
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingServer = server
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(server)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("服务器管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerView()
        }
        .sheet(item: $editingServer) { server in
            AddServerView(serverToEdit: server)
        }
        .onAppear {
            // Initial sync and check
            appStateManager.updateServers(servers)
            appStateManager.checkServerStatus()
        }
        .onChange(of: servers) { _, newServers in
            // Sync when list changes (add/delete)
            appStateManager.updateServers(newServers)
            appStateManager.checkServerStatus()
        }
    }
}

struct ServerCardRow: View {
    var server: ServerConfig
    @State private var isBreathing = false
    
    @Environment(AppStateManager.self) private var appStateManager
    
    var statusColor: Color {
        if let isOnline = server.isOnline {
            return isOnline ? .green : .red
        }
        return .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                // Status Dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .opacity(server.isOnline == nil ? (isBreathing ? 0.3 : 1.0) : 1.0)
                    .onAppear {
                        if server.isOnline == nil {
                            withAnimation(.easeInOut(duration: 1).repeatForever()) {
                                isBreathing = true
                            }
                        }
                    }
                    .onChange(of: server.isOnline) { oldValue, newValue in
                        if newValue != nil {
                            isBreathing = false
                        }
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(server.address):\(String(server.port))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Type Badge
                Text(server.type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            
            if server.isOnline == false {
                Text("连接超时，请检查网络或穿透设置")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .padding(.leading, 42) // Align with text (16 spacing + 10 dot + 16 internal spacing) approx
                    .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    NavigationStack {
        ServerListView()
            .modelContainer(for: ServerConfig.self, inMemory: true)
    }
}
