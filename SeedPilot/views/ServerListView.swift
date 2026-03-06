//
//  ServerListView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import SwiftData
import UIKit

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appStateManager
    @Query private var servers: [ServerConfig]
    @AppStorage("isProUser") private var isProUser: Bool = false
    @AppStorage("hideServerAddress") private var hideServerAddress: Bool = false

    @State private var showingAddServer = false
    @State private var showingProPaywall = false
    @State private var editingServer: ServerConfig?
    @State private var rateLimitServer: ServerConfig?
    @State private var connectionSettingsServer: ServerConfig?
    @State private var downloadSettingsServer: ServerConfig?
    @State private var taxonomyServer: ServerConfig?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(appStateManager.servers) { server in
                    Button {
                        selectServer(server)
                    } label: {
                        ServerCardView(server: server)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button {
                            editingServer = server
                        } label: {
                            Label(LanguageManager.shared.localized("Edit Server"), systemImage: "square.and.pencil")
                        }

                        Button {
                            rateLimitServer = server
                        } label: {
                            Label(LanguageManager.shared.localized("Rate Limit Settings"), systemImage: "speedometer")
                        }

                        Button {
                            connectionSettingsServer = server
                        } label: {
                            Label(LanguageManager.shared.localized("Connection Settings"), systemImage: "network")
                        }

                        Button {
                            downloadSettingsServer = server
                        } label: {
                            Label(LanguageManager.shared.localized("Download Settings"), systemImage: "folder.badge.gearshape")
                        }

                        Button {
                            taxonomyServer = server
                        } label: {
                            Label(
                                LanguageManager.shared.localized(server.type == .qBittorrent ? "Category & Tags Settings" : "Tag Settings"),
                                systemImage: "tag"
                            )
                        }

                        Button(role: .destructive) {
                            server.deleteResolvedPassword()
                            modelContext.delete(server)
                        } label: {
                            Label(LanguageManager.shared.localized("Delete Server"), systemImage: "trash")
                        }
                    }
                }

                // Add Server Tile
                Button {
                    handleAddServerTapped()
                } label: {
                    AddServerTile()
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(LanguageManager.shared.localized("Server Management"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hideServerAddress.toggle()
                    }
                } label: {
                    Image(systemName: hideServerAddress ? "eye.slash.fill" : "eye")
                        .foregroundStyle(hideServerAddress ? .secondary : .primary)
                }

                Button {
                    handleAddServerTapped()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            EditServerView()
        }
        .sheet(isPresented: $showingProPaywall) {
            ProView(isPresentedAsSheet: true)
                .ignoresSafeArea()
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(item: $editingServer) { server in
            EditServerView(serverToEdit: server)
        }
        .sheet(item: $rateLimitServer) { server in
            ServerRateLimitView(server: server)
        }
        .sheet(item: $connectionSettingsServer) { server in
            ConnectionSettingsView(server: server)
        }
        .sheet(item: $downloadSettingsServer) { server in
            DownloadSettingsView(server: server)
        }
        .sheet(item: $taxonomyServer) { server in
            NavigationStack {
                ServerTaxonomySettingsView(server: server)
            }
        }
        .onAppear {
            ServerConfigCloudSyncManager.shared.start(with: modelContext)
            ServerConfigCloudSyncManager.shared.reconcileOnLaunchOrBecomeActive()
            appStateManager.updateServers(servers)
            appStateManager.checkServerStatus()
        }
        .onChange(of: servers) { _, newServers in
            ServerConfigCloudSyncManager.shared.handleLocalServerListChanged(newServers)
            appStateManager.updateServers(newServers)
            appStateManager.checkServerStatus()
        }
    }

    // Logic extracted from DashboardView
    private func selectServer(_ server: ServerConfig) {
        withAnimation {
            appStateManager.activeServerId = server.id
            appStateManager.selectedTab = .transfers
        }
    }

    private func handleAddServerTapped() {
        let serverCount = max(servers.count, appStateManager.servers.count)
        if !isProUser && serverCount >= 2 {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            showingProPaywall = true
            return
        }
        showingAddServer = true
    }
}

struct ServerCardView: View {
    let server: ServerConfig
    @AppStorage("hideServerAddress") private var hideServerAddress: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            HStack(alignment: .top) {
                // Logo & Title
                HStack(spacing: 8) {
                    Group {
                        if server.type == .transmission {
                            if UIImage(named: "tr_logo") != nil {
                                Image("tr_logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            if UIImage(named: "qb_logo") != nil {
                                Image("qb_logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "network")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .frame(width: 32, height: 32)

                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                // Status Dot
                Circle()
                    .fill(server.statusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.bottom, 2)

            // Subheadline (URL)
            Text(hideServerAddress ? "••••••••" : server.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())

            Spacer()

            // MARK: - Data Matrix
            VStack(spacing: 8) {
                // Row 1: Upload / Download
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2.bold())
                        Text("\(server.totalSeedingCount)")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption2.bold())
                        Text("\(server.totalDownloadingCount)")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }

                // Row 2: Size / Ratio
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.caption2)
                        Text(formatBytes(server.totalSeedingSize))
                            .font(.caption.monospacedDigit())
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption2)
                        Text(String(format: "%.2f", server.totalRatio))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12) // Compact padding
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct AddServerTile: View {
    var body: some View {
        VStack {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))

            Text(LanguageManager.shared.localized("Add Server"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .background(Color.clear) // Clear BG
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.secondary.opacity(0.3))
        )
    }
}
