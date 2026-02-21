import SwiftUI

struct TorrentActionSheetView: View {
    let task: TorrentTask
    let posterURL: URL?
    let appStateManager: AppStateManager
    let onPosterChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingTrackersAlert = false
    @State private var newTrackers = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingSetSavePathSheet = false
    @State private var showingManualMatchSheet = false
    @State private var draftSavePath = ""

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    private var pauseOrResumeTitle: String {
        task.status == .paused
            ? languageManager.localized("Resume")
            : languageManager.localized("Pause")
    }

    private var pauseOrResumeIcon: String {
        task.status == .paused ? "play.fill" : "pause.fill"
    }

    var body: some View {
        VStack(spacing: 16) {
            header
                .padding(.top, 20)

            quickActions

            List {
                Section {
                    Button {
                        newName = task.name
                        showingRenameAlert = true
                    } label: {
                        Label(languageManager.localized("Rename"), systemImage: "square.and.pencil")
                    }
                    .alert(languageManager.localized("Rename Task"), isPresented: $showingRenameAlert) {
                        TextField(languageManager.localized("New Name"), text: $newName)
                        Button(languageManager.localized("Cancel"), role: .cancel) {}
                        Button(languageManager.localized("Confirm")) {
                            appStateManager.renameTask(task, newName: newName)
                        }
                    } message: {
                        Text(languageManager.localized("Please enter a new task name."))
                    }

                    Button {
                        draftSavePath = task.savePath
                        showingSetSavePathSheet = true
                    } label: {
                        Label(languageManager.localized("Set Save Path"), systemImage: "folder.badge.gear")
                    }
                }

                Section {
                    Button {
                        newTrackers = task.tracker
                        showingTrackersAlert = true
                    } label: {
                        Label(languageManager.localized("Edit Tracker"), systemImage: "network.badge.shield.half.filled")
                    }
                    .alert(languageManager.localized("Edit Tracker"), isPresented: $showingTrackersAlert) {
                        TextField(languageManager.localized("Tracker URL"), text: $newTrackers)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(languageManager.localized("Cancel"), role: .cancel) {}
                        Button(languageManager.localized("Confirm")) {
                            appStateManager.editTrackers(task, newTrackers: newTrackers)
                        }
                    } message: {
                        Text(languageManager.localized("Please enter Tracker URL. For multiple URLs, try comma separation if supported by your server."))
                    }

                    Button {
                        onPosterChanged()
                    } label: {
                        Label(languageManager.localized("Rematch Poster"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        showingManualMatchSheet = true
                    } label: {
                        Label(languageManager.localized("Manual Match Poster"), systemImage: "photo.badge.plus")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label {
                            Text(languageManager.localized("Delete"))
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .confirmationDialog(languageManager.localized("Confirm Deletion"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(languageManager.localized("Delete Task (Keep Data)"), role: .destructive) {
                appStateManager.deleteTask(task, withData: false)
                dismiss()
            }
            Button(languageManager.localized("Delete Task and Data"), role: .destructive) {
                appStateManager.deleteTask(task, withData: true)
                dismiss()
            }
            Button(languageManager.localized("Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: languageManager.localized("Are you sure you want to delete this task? %@"), task.name))
        }
        .sheet(isPresented: $showingSetSavePathSheet) {
            TorrentSavePathEditorView(
                path: $draftSavePath,
                presetSavePaths: presetSavePaths,
                onConfirm: { path in
                    appStateManager.setLocation(task, newLocation: path)
                    dismiss()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingManualMatchSheet) {
            ManualMatchView(taskName: task.name, taskHash: task.id)
                .presentationDetents([.medium, .large])
                .onDisappear {
                    onPosterChanged()
                }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let posterURL {
                    SimpleCachedImage(url: posterURL)
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 68, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(task.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(task.status.localizedDisplayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickActionButton(title: pauseOrResumeTitle, systemImage: pauseOrResumeIcon) {
                if task.status == .paused {
                    appStateManager.resumeTask(task)
                } else {
                    appStateManager.pauseTask(task)
                }
                dismiss()
            }

            quickActionButton(title: languageManager.localized("Force Start"), systemImage: "forward.end.fill") {
                appStateManager.forceStartTask(task)
                dismiss()
            }
        }
        .padding(.horizontal, 16)
    }

    private func quickActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TorrentSavePathEditorView: View {
    @Binding var path: String
    let presetSavePaths: [String]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    private var presetSelection: Binding<String> {
        Binding(
            get: { presetSavePaths.contains(path) ? path : (presetSavePaths.first ?? "") },
            set: { path = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(languageManager.localized("Path"), text: $path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if presetSavePaths.isEmpty {
                        Label(languageManager.localized("No Preset Save Paths"), systemImage: "folder.fill")
                            .foregroundStyle(.secondary)
                    } else if presetSavePaths.count == 1, let onlyPath = presetSavePaths.first {
                        Button {
                            path = onlyPath
                        } label: {
                            HStack {
                                Label(languageManager.localized("Choose Preset Path"), systemImage: "folder.fill")
                                Spacer()
                                Text(onlyPath)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    } else {
                        Picker(selection: presetSelection) {
                            ForEach(presetSavePaths, id: \.self) { presetPath in
                                Text(presetPath).tag(presetPath)
                            }
                        } label: {
                            Label(languageManager.localized("Choose Preset Path"), systemImage: "folder.fill")
                        }
                        .pickerStyle(.menu)
                    }
                } footer: {
                    Text(languageManager.localized("Please enter a new absolute path (e.g. /downloads/movie)."))
                }
            }
            .navigationTitle(languageManager.localized("Set Save Path"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Confirm")) {
                        onConfirm(path)
                        dismiss()
                    }
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
