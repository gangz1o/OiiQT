import SwiftUI

struct TorrentActionSheetView: View {
    let task: TorrentTask
    let posterURL: URL?
    let appStateManager: AppStateManager
    let onPosterChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"
    @AppStorage("showTMDBData") private var showTMDBData: Bool = false

    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingTrackersAlert = false
    @State private var newTrackers = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingSetSavePathSheet = false
    @State private var showingManualMatchSheet = false
    @State private var showingCategorySelector = false
    @State private var showingTagSelector = false
    @State private var draftSavePath = ""
    @State private var categoryOptions: [String] = []
    @State private var tagOptions: [String] = []
    @State private var selectedCategory = ""
    @State private var selectedTags: Set<String> = []
    @State private var taxonomyErrorMessage = ""
    @State private var showingTaxonomyError = false
    @State private var displayPosterURL: URL?
    @State private var isAutoMatching = false
    @State private var showingSpeedLimitSheet = false

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

    private var taskServerType: ServerType? {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.type
    }

    private var supportsCategory: Bool {
        taskServerType == .qBittorrent
    }

    private var supportsTags: Bool {
        taskServerType == .qBittorrent || taskServerType == .transmission
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
                        sheetMenuRow(
                            title: languageManager.localized("Rename"),
                            systemImage: "square.and.pencil"
                        )
                    }
                    .buttonStyle(.plain)
                    .alert(languageManager.localized("Rename Task"), isPresented: $showingRenameAlert) {
                        TextField(languageManager.localized("New Name"), text: $newName)
                        Button(languageManager.localized("Cancel"), role: .cancel) {}
                        Button(languageManager.localized("Confirm")) {
                            appStateManager.renameTask(task, newName: newName)
                            DispatchQueue.main.async { dismiss() }
                        }
                    } message: {
                        Text(languageManager.localized("Please enter a new task name."))
                    }

                    Button {
                        draftSavePath = task.savePath
                        appStateManager.stopAutoRefresh()
                        showingSetSavePathSheet = true
                    } label: {
                        sheetMenuRow(
                            title: languageManager.localized("Set Save Path"),
                            systemImage: "folder.badge.gear"
                        )
                    }
                    .buttonStyle(.plain)

                    if supportsCategory {
                        Button {
                            handleSetCategoryTapped()
                        } label: {
                            sheetMenuRow(
                                title: languageManager.localized("Set Category"),
                                systemImage: "tray.full"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if supportsTags {
                        Button {
                            handleEditTagsTapped()
                        } label: {
                            sheetMenuRow(
                                title: languageManager.localized("Edit Tags"),
                                systemImage: "tag"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        newTrackers = trackerDraftValue(from: task.tracker)
                        showingTrackersAlert = true
                    } label: {
                        sheetMenuRow(
                            title: languageManager.localized("Edit Tracker"),
                            systemImage: "network.badge.shield.half.filled"
                        )
                    }
                    .buttonStyle(.plain)
                    .alert(languageManager.localized("Edit Tracker"), isPresented: $showingTrackersAlert) {
                        TextField(languageManager.localized("Tracker URL"), text: $newTrackers)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(languageManager.localized("Cancel"), role: .cancel) {}
                        Button(languageManager.localized("Confirm")) {
                            appStateManager.editTrackers(task, newTrackers: newTrackers)
                            DispatchQueue.main.async { dismiss() }
                        }
                    } message: {
                        Text(languageManager.localized("Please enter Tracker URL. For multiple URLs, try comma separation if supported by your server."))
                    }

                    Button {
                        showingSpeedLimitSheet = true
                    } label: {
                        sheetMenuRow(
                            title: languageManager.localized("Speed Limit"),
                            systemImage: "speedometer"
                        )
                    }
                    .buttonStyle(.plain)

                    if showTMDBData {
                        Button {
                            guard !isAutoMatching else { return }
                            isAutoMatching = true
                            Task {
                                defer { isAutoMatching = false }
                                TMDBService.shared.clearPosterMatch(for: task.hash, context: modelContext)
                                let newURL = await TMDBService.shared.fetchPoster(hash: task.hash, name: task.name, context: modelContext)
                                if let newURL {
                                    displayPosterURL = newURL
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } else {
                                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                                }
                                onPosterChanged()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if isAutoMatching {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .imageScale(.medium)
                                        .foregroundStyle(.secondary)
                                }
                                Text(languageManager.localized("Rematch Poster"))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAutoMatching)

                        Button {
                            showingManualMatchSheet = true
                        } label: {
                            sheetMenuRow(
                                title: languageManager.localized("Manual Match Poster"),
                                systemImage: "photo.badge.plus"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .imageScale(.medium)
                                .foregroundStyle(.red)
                            Text(languageManager.localized("Delete"))
                                .font(.body)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(Color(uiColor: .systemBackground))
        .confirmationDialog(languageManager.localized("Confirm Deletion"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(languageManager.localized("Delete Task (Keep Data)"), role: .destructive) {
                appStateManager.deleteTask(task, withData: false)
                DispatchQueue.main.async { dismiss() }
            }
            Button(languageManager.localized("Delete Task and Data"), role: .destructive) {
                appStateManager.deleteTask(task, withData: true)
                DispatchQueue.main.async { dismiss() }
            }
            Button(languageManager.localized("Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: languageManager.localized("Are you sure you want to delete this task? %@"), task.name))
        }
        .sheet(isPresented: $showingSetSavePathSheet, onDismiss: {
            appStateManager.startAutoRefresh()
        }) {
            TorrentSavePathEditorView(
                isPresented: $showingSetSavePathSheet,
                path: $draftSavePath,
                presetSavePaths: presetSavePaths,
                onConfirm: { path in
                    appStateManager.setLocation(task, newLocation: path)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: Binding(
                get: { showTMDBData && showingManualMatchSheet },
                set: { showingManualMatchSheet = $0 }
            )
        ) {
            ManualMatchView(taskName: task.name, taskHash: task.hash)
                .presentationDetents([.medium, .large])
                .onDisappear {
                    Task {
                        let newURL = await TMDBService.shared.fetchPoster(hash: task.hash, name: task.name, context: modelContext)
                        if let newURL {
                            displayPosterURL = newURL
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        onPosterChanged()
                    }
                }
        }
        .sheet(isPresented: $showingCategorySelector) {
            CategorySelectionSheetView(
                categories: categoryOptions,
                initialSelection: selectedCategory
            ) { category in
                Task {
                    await applyCategory(category)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingTagSelector) {
            TagMultiSelectSheetView(
                availableTags: tagOptions,
                initialSelection: selectedTags
            ) { tags in
                Task {
                    await applyTags(tags)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSpeedLimitSheet) {
            TorrentSpeedLimitSheet(
                task: task,
                appStateManager: appStateManager
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert(languageManager.localized("Error"), isPresented: $showingTaxonomyError) {
            Button(languageManager.localized("OK"), role: .cancel) {}
        } message: {
            Text(taxonomyErrorMessage)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if showTMDBData {
                Group {
                    if let url = displayPosterURL {
                        SimpleCachedImage(url: url)
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
            }

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
        .onAppear {
            guard showTMDBData else {
                displayPosterURL = nil
                return
            }

            displayPosterURL = posterURL
            if displayPosterURL == nil {
                Task {
                    let newURL = await TMDBService.shared.fetchPoster(hash: task.hash, name: task.name, context: modelContext)
                    if let newURL = newURL {
                        displayPosterURL = newURL
                    }
                }
            }
        }
        .onChange(of: posterURL) { _, newURL in
            guard showTMDBData else { return }
            if let newURL = newURL, displayPosterURL == nil {
                displayPosterURL = newURL
            }
        }
        .onChange(of: showTMDBData) { _, isEnabled in
            if !isEnabled {
                displayPosterURL = nil
                showingManualMatchSheet = false
            } else if let posterURL {
                displayPosterURL = posterURL
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickActionButton(title: pauseOrResumeTitle, systemImage: pauseOrResumeIcon) {
                if task.status == .paused {
                    appStateManager.resumeTask(task)
                } else {
                    appStateManager.pauseTask(task)
                }
                DispatchQueue.main.async { dismiss() }
            }

            quickActionButton(title: languageManager.localized("Force Start"), systemImage: "forward.end.fill") {
                appStateManager.forceStartTask(task)
                DispatchQueue.main.async { dismiss() }
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

    private func sheetMenuRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func handleSetCategoryTapped() {
        guard supportsCategory else { return }
        Task {
            do {
                let categories = try await appStateManager.fetchTaskCategoryOptions(for: task)
                await MainActor.run {
                    categoryOptions = categories
                    selectedCategory = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    showingCategorySelector = true
                }
            } catch {
                await MainActor.run {
                    taxonomyErrorMessage = localizedErrorMessage(error)
                    showingTaxonomyError = true
                }
            }
        }
    }

    private func handleEditTagsTapped() {
        guard supportsTags else { return }
        Task {
            do {
                let fetchedOptions = try await appStateManager.fetchTaskTagOptions(for: task)
                let current = parseTags(task.tags)
                await MainActor.run {
                    selectedTags = Set(current)
                    tagOptions = Array(Set(fetchedOptions).union(selectedTags))
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    showingTagSelector = true
                }
            } catch {
                await MainActor.run {
                    taxonomyErrorMessage = localizedErrorMessage(error)
                    showingTaxonomyError = true
                }
            }
        }
    }

    private func applyCategory(_ category: String) async {
        do {
            try await appStateManager.applyCategory(category, to: task)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                taxonomyErrorMessage = localizedErrorMessage(error)
                showingTaxonomyError = true
            }
        }
    }

    private func applyTags(_ tags: [String]) async {
        do {
            try await appStateManager.applyTags(tags, to: task)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                taxonomyErrorMessage = localizedErrorMessage(error)
                showingTaxonomyError = true
            }
        }
    }

    private func parseTags(_ raw: String) -> [String] {
        Array(
            Set(
                raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func trackerDraftValue(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard isLikelyTrackerURL(trimmed) else { return "" }
        return trimmed
    }

    private func isLikelyTrackerURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return false
        }

        return ["http", "https", "udp", "ws", "wss"].contains(scheme)
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if case let TorrentClientError.apiError(message) = error {
            return languageManager.localized(message)
        }
        return error.localizedDescription
    }

}

private struct TorrentSavePathEditorView: View {
    @Binding var isPresented: Bool
    @Binding var path: String
    let presetSavePaths: [String]
    let onConfirm: (String) -> Void

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
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Confirm")) {
                        onConfirm(path)
                        isPresented = false
                    }
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
