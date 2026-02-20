//
//  TorrentRowView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/14.
//

import SwiftUI

struct TorrentRowView: View {
    let task: TorrentTask
    let isSelected: Bool
    let isEditing: Bool
    let toggleSelection: () -> Void

    @AppStorage("showTMDBData") private var showTMDBData: Bool = false
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var trackerAliasManager = TrackerAliasManager.shared
    var appStateManager: AppStateManager

    @State private var posterURL: URL?
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingLocationAlert = false
    @State private var newLocation = ""
    @State private var showingTrackersAlert = false
    @State private var newTrackers = ""
    @State private var showingDeleteConfirmation = false
    @State private var isLoadingPoster = false
    @State private var showingManualMatchSheet = false

    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Checkbox (Edit Mode Only)
            if isEditing {
                Button {
                    toggleSelection()
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                        .contentShape(Rectangle()) // Make touch area larger
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .padding(.leading, 8)
            }

            // MARK: - Content
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // MARK: - 1. Left Poster Area
                    if showTMDBData {
                        posterArea
                    }

                    // MARK: - 2. Right Content Area
                    VStack(alignment: .leading, spacing: 8) {
                        // Feature 1: Top Status Bar
                        HStack {
                            // Tracker
                            Text(displayedTracker)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())

                            // Seeding Time / Added Date if not seeding
                            if task.status == .seeding {
                                 HStack(spacing: 2) {
                                    Image(systemName: "clock")
                                    Text(task.seedingTimeString)
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Status & Percent
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(task.status.localizedDisplayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(task.percentString)
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(statusColor)
                            }
                        }

                        // Title
                        let titleText = Text(task.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)

                        if appStateManager.activeServerId == nil,
                           let serverName = appStateManager.servers.first(where: { $0.id == task.serverID })?.name {
                            Text(
                                "\(titleText)  \(Text(serverName).font(.caption).foregroundStyle(.secondary))"
                            )
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            titleText
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Feature 3: Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5))
                                Capsule().fill(statusColor)
                                    .frame(width: max(0, geo.size.width * CGFloat(task.progress)))
                                    .animation(.smooth, value: task.progress)
                            }
                        }
                        .frame(height: 4) // Slimmer

                        // Feature 2: 3x2 Data Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], spacing: 6) {
                            // Row 1
                            GridRowIconText(icon: "arrow.down.circle", text: formatBytes(task.downloadSpeed) + "/s", color: .secondary)
                            GridRowIconText(icon: "arrow.down", text: "\(task.numPeers)/\(task.totalPeers)", color: .secondary) // Peers
                            GridRowIconText(icon: "doc", text: task.sizeString, color: .secondary) // Size

                            // Row 2
                            GridRowIconText(icon: "arrow.up.circle", text: formatBytes(task.uploadSpeed) + "/s", color: .secondary)
                            GridRowIconText(icon: "leaf", text: "\(task.numSeeds)/\(task.totalSeeds)", color: .secondary) // Seeds
                            GridRowIconText(icon: "arrow.left.and.right", text: String(format: "%.2f", task.ratio), color: .secondary) // Ratio
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground)) // Card background
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2) // Subtle shadow
        }
        .contentShape(Rectangle()) // Make the whole row tappable
        .gesture(
            isEditing ? TapGesture().onEnded {
                toggleSelection()
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } : nil
        )
        .contextMenu {
            if !isEditing {
                if task.status == .paused {
                    Button {
                        appStateManager.resumeTask(task)
                    } label: {
                        Label(LanguageManager.shared.localized("Resume"), systemImage: "play.fill")
                    }
                } else {
                    Button {
                        appStateManager.pauseTask(task)
                    } label: {
                        Label(LanguageManager.shared.localized("Pause"), systemImage: "pause.fill")
                    }
                }

                Divider()

                Button {
                    newName = task.name
                    showingRenameAlert = true
                } label: {
                    Label(LanguageManager.shared.localized("Rename"), systemImage: "pencil")
                }

                Menu {
                    // Advanced Tools Submenu
                    Menu {
                        Button {
                            appStateManager.recheckTask(task)
                        } label: {
                            Label(LanguageManager.shared.localized("Force Recheck"), systemImage: "checkmark.seal")
                        }

                        Button {
                            appStateManager.reannounceTask(task)
                        } label: {
                            Label(LanguageManager.shared.localized("Force Reannounce"), systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label(LanguageManager.shared.localized("Advanced Tools"), systemImage: "gearshape.2")
                    }

                    // Download Settings Submenu
                    Menu {
                        Button {
                            appStateManager.toggleSequentialDownload(task)
                        } label: {
                            let icon = (task.isSequential == true) ? "checkmark" : "arrow.down.to.line"
                            Label(LanguageManager.shared.localized("Sequential Download"), systemImage: icon)
                        }

                        Button {
                            appStateManager.toggleFirstLastPiecePriority(task)
                        } label: {
                            let icon = (task.isFirstLastPiecePriority == true) ? "checkmark" : "arrow.up.arrow.down.square"
                            Label(LanguageManager.shared.localized("First/Last Piece Priority"), systemImage: icon)
                        }
                    } label: {
                        Label(LanguageManager.shared.localized("Download Settings"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Label(LanguageManager.shared.localized("More Actions"), systemImage: "ellipsis.circle")
                }

                Divider()

                Button {
                    appStateManager.forceStartTask(task)
                } label: {
                    Label(LanguageManager.shared.localized("Force Start"), systemImage: "bolt.fill")
                }

                Button {
                    newLocation = task.savePath
                    showingLocationAlert = true
                } label: {
                    Label(LanguageManager.shared.localized("Set Save Path"), systemImage: "folder.badge.gear")
                }

                Button {
                    newTrackers = task.tracker
                    showingTrackersAlert = true
                } label: {
                    Label(LanguageManager.shared.localized("Edit Tracker"), systemImage: "network.badge.shield.half.filled")
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
                }

                Divider()

                if showTMDBData {
                    Button {
                        TMDBService.shared.clearCache(for: task.id)
                        Task { await refreshPosterAsync() }
                    } label: {
                        Label(LanguageManager.shared.localized("Rematch Poster"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        showingManualMatchSheet = true
                    } label: {
                        Label(LanguageManager.shared.localized("Manual Match Poster"), systemImage: "photo.badge.plus")
                    }
                }
            }
        }
        .alert(LanguageManager.shared.localized("Rename Task"), isPresented: $showingRenameAlert) {
            TextField(LanguageManager.shared.localized("New Name"), text: $newName)
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                appStateManager.renameTask(task, newName: newName)
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter a new task name."))
        }
        .alert(LanguageManager.shared.localized("Set Save Path"), isPresented: $showingLocationAlert) {
            TextField(LanguageManager.shared.localized("Path"), text: $newLocation)
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                appStateManager.setLocation(task, newLocation: newLocation)
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter a new absolute path (e.g. /downloads/movie)."))
        }
        .alert(LanguageManager.shared.localized("Edit Tracker"), isPresented: $showingTrackersAlert) {
            TextField(LanguageManager.shared.localized("Tracker URL"), text: $newTrackers)
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
            Button(LanguageManager.shared.localized("Confirm")) {
                appStateManager.editTrackers(task, newTrackers: newTrackers)
            }
        } message: {
            Text(LanguageManager.shared.localized("Please enter Tracker URL. For multiple URLs, try comma separation if supported by your server."))
        }
        .sheet(isPresented: $showingManualMatchSheet) {
            ManualMatchView(taskName: task.name, taskHash: task.id)
                .presentationDetents([.medium, .large])
                .onDisappear {
                    TMDBService.shared.clearCache(for: task.id)
                    Task { await refreshPosterAsync() }
                }
        }
        .confirmationDialog(LanguageManager.shared.localized("Confirm Deletion"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(LanguageManager.shared.localized("Delete Task (Keep Data)"), role: .destructive) {
                appStateManager.deleteTask(task, withData: false)
            }
            Button(LanguageManager.shared.localized("Delete Task and Data"), role: .destructive) {
                appStateManager.deleteTask(task, withData: true)
            }
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) { }
        } message: {
            Text(String(format: LanguageManager.shared.localized("Are you sure you want to delete this task? %@"), task.name))
        }
        .task(id: "\(task.name)-\(languageManager.selectedLanguage.rawValue)") {
            await refreshPosterAsync()
        }
    }

    private func refreshPosterAsync() async {
        guard showTMDBData else { return }
        isLoadingPoster = true
        let url = await TMDBService.shared.fetchPoster(hash: task.id, name: task.name, context: modelContext)
        if !Task.isCancelled {
            self.posterURL = url
            self.isLoadingPoster = false
        }
    }

    // MARK: - Components

    private var posterArea: some View {
        Group {
            if let url = posterURL {
                SimpleCachedImage(url: url)
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingPoster {
                SeedPilotPlaceholder()
                    .overlay { ProgressView() }
            } else {
                SeedPilotPlaceholder()
                    .overlay {
                        Image(systemName: "sparkles.tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            }
        }
        .frame(width: 65, height: 97.5)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var speedCapsule: some View {
        HStack(spacing: 4) {
            if task.status == .downloading {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(formatBytes(task.downloadSpeed) + "/s")
            } else if task.status == .seeding {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(formatBytes(task.uploadSpeed) + "/s")
            } else {
                Text(task.status.localizedDisplayName)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .seeding: return .green
        case .checking: return .orange
        case .error: return .red
        default: return Color.gray.opacity(0.8)
        }
    }
}

private extension TorrentRowView {
    var displayedTracker: String {
        trackerAliasManager.getAlias(for: task.trackerHost)
    }
}

// Helper View for Tags
struct TagCapsule: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
}

struct GridRowIconText: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
