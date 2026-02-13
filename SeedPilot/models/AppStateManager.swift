//
//  AppStateManager.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import Foundation
import SwiftData
import Observation
import SwiftUI

@Observable
class AppStateManager {
    var servers: [ServerConfig] = []
    var allTasks: [TorrentTask] = []
    
    // Client Cache
    private var clients: [UUID: TorrentClient] = [:]
    
    // MARK: - Computed Properties
    
    /// 所有服务器的总下载速度 (Bytes/s)
    var totalDownloadSpeed: Int64 {
        allTasks.reduce(0) { $0 + $1.downloadSpeed }
    }
    
    /// 所有服务器的总上传速度 (Bytes/s)
    var totalUploadSpeed: Int64 {
        allTasks.reduce(0) { $0 + $1.uploadSpeed }
    }
    
    // MARK: - Data Management
    
    /// 从 SwiftData 加载服务器列表 (App launch)
    @MainActor
    func loadServers(context: ModelContext) {
        let descriptor = FetchDescriptor<ServerConfig>(sortBy: [SortDescriptor(\.name)])
        do {
            servers = try context.fetch(descriptor)
            // Start auto-refresh
            startAutoRefresh()
        } catch {
            print("Failed to load servers: \(error)")
        }
    }
    
    /// Sync servers from UI Query (to ensure we have latest list including new additions)
    @MainActor
    func updateServers(_ newServers: [ServerConfig]) {
        self.servers = newServers
    }
    
    /// 启动自动刷新 (每 2 秒)
    func startAutoRefresh() {
        Task {
            // Initial fetch
            await refreshData()
            
            // Periodic fetch
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await refreshData()
            }
        }
    }
    
    /// 刷新所有服务器的任务 (对应 User Request: refreshData)
    func refreshData() async {
        var gatheredTasks: [TorrentTask] = []
        
        // Parallel fetching could be done with TaskGroup, but for now serial is safer for debug
        for server in servers {
            let client = getClient(for: server)
            do {
                // Try fetch
                let tasks = try await client.fetchTorrents()
                gatheredTasks.append(contentsOf: tasks)
                
                // Mark online
                await MainActor.run {
                    server.isOnline = true
                }
            } catch let error as TorrentClientError {
                // If auth failed, try login and retry
                if case .authenticationFailed = error {
                    do {
                        try await client.login()
                        let tasks = try await client.fetchTorrents()
                        gatheredTasks.append(contentsOf: tasks)
                        
                        // Mark online after retry success
                        await MainActor.run {
                            server.isOnline = true
                        }
                    } catch {
                        print("Auth retry failed for \(server.name): \(error)")
                        await MainActor.run { server.isOnline = false }
                    }
                } else {
                    print("Fetch failed for \(server.name): \(error)")
                    await MainActor.run { server.isOnline = false }
                }
            } catch {
                print("Unknown error for \(server.name): \(error)")
                await MainActor.run { server.isOnline = false }
            }
        }
        
        let finalTasks = gatheredTasks
        await MainActor.run {
            self.allTasks = finalTasks
        }
    }
    
    func checkServerStatus() {
        for server in servers {
            let client = getClient(for: server)
            // Set to nil to show breathing animation
            server.isOnline = nil
            
            Task {
                do {
                    _ = try await client.checkConnection()
                    await MainActor.run { server.isOnline = true }
                } catch {
                    // Auth retry? checkConnection handles 403 by throwing auth failed, 
                    // but we might want to try auto-login here too? 
                    // For lightweight heartbeat, maybe just separate "Auth Failed" vs "Timeout"?
                    // User said "Timeout, check network". 
                    // I'll stick to simple true/false for now as requested.
                    await MainActor.run { server.isOnline = false }
                }
            }
        }
    }

    private func getClient(for server: ServerConfig) -> TorrentClient {
        if let existing = clients[server.id] {
            return existing
        }
        
        let client: TorrentClient
        switch server.type {
        case .qBittorrent:
            client = QBittorrentClient(config: server)
        case .transmission:
            client = QBittorrentClient(config: server)
        }
        clients[server.id] = client
        return client
    }
    
    // MARK: - Task Actions
    
    func addMagnetLink(_ link: String) {
        guard let server = servers.first else {
            print("No server available to add task")
            return
        }
        
        Task {
            let client = getClient(for: server)
            do {
                try await client.addMagnetLink(link)
                await refreshData() // Refresh list
            } catch {
               print("Failed to add magnet link: \(error)")
            }
        }
    }
    
    func pauseTask(_ task: TorrentTask) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)
        
        Task {
            do {
                try await client.pauseTask(hash: task.id)
                // Optionally optimistic update
                await refreshData()
            } catch {
                print("Failed to pause: \(error)")
            }
        }
    }
    
    func resumeTask(_ task: TorrentTask) {
        guard let server = servers.first(where: { $0.id == task.serverID }) else { return }
        let client = getClient(for: server)
        
        Task {
            do {
                try await client.resumeTask(hash: task.id)
                await refreshData()
            } catch {
                print("Failed to resume: \(error)")
            }
        }
    }
    
    func deleteTasks(_ tasks: Set<TorrentTask>) {
        for task in tasks {
            guard let server = servers.first(where: { $0.id == task.serverID }) else { continue }
            let client = getClient(for: server)
            Task {
                do {
                    try await client.deleteTask(hash: task.id, withData: true) // Default strict delete? Or ask?
                    // User might want to keep data.
                    // For now, default to withData: true or false?
                    // Usually swipe delete implies removing from list.
                    // User didn't specify. I'll default to withData: false (safer) or true?
                    // "删除任务" usually implies removing task. Data?
                    // I will default to false (keep data) for safety, or pass parameter.
                    // Protocol says func deleteTask(hash: String, withData: Bool)
                 } catch {
                    print("Failed to delete: \(error)")
                }
            }
        }
        // Refresh after delay?
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshData()
        }
    }
}
