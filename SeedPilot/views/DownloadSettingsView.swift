import SwiftUI
import UIKit

struct DownloadSettingsView: View {
    let server: ServerConfig

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appStateManager
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var toastMessage: String?
    @State private var toastAutoHideTask: Task<Void, Never>?

    @State private var savePath = ""
    @State private var appendExtension = false
    @State private var useTempPath = false
    @State private var tempPath = ""
    @State private var preallocateAll = false
    @State private var cacheSizeMB = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(languageManager.localized("Default Path")) {
                    TextField(languageManager.localized("Default Save Path"), text: $savePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(languageManager.localized("Incomplete Torrents")) {
                    Toggle(languageManager.localized("Append incomplete extension"), isOn: $appendExtension)

                    Toggle(languageManager.localized("Use temporary directory"), isOn: $useTempPath)

                    if useTempPath {
                        TextField(languageManager.localized("Temporary Path"), text: $tempPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut, value: useTempPath)

                Section(languageManager.localized("Advanced")) {
                    if server.type == .qBittorrent {
                        Toggle(languageManager.localized("Pre-allocate disk space"), isOn: $preallocateAll)
                    } else {
                        Stepper(value: $cacheSizeMB, in: 0...8192, step: 16) {
                            HStack {
                                Text(languageManager.localized("Disk Cache Size"))
                                Spacer()
                                Text("\(cacheSizeMB) \(languageManager.localized("MB"))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .disabled(isLoading || isSaving)
            .overlay {
                if isLoading {
                    ZStack {
                        Color(uiColor: .systemBackground).opacity(0.9)
                        ProgressView(languageManager.localized("Loading..."))
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationTitle(languageManager.localized("Download Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(languageManager.localized("Save")) {
                            Task {
                                await saveSettings()
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .alert(languageManager.localized("Error"), isPresented: $showingErrorAlert) {
                Button(languageManager.localized("OK"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task(id: server.id) {
            await loadSettings()
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .onDisappear {
            toastAutoHideTask?.cancel()
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let settings = try await appStateManager.fetchDownloadSettings(for: server)
            savePath = settings.savePath
            appendExtension = settings.appendExtension
            useTempPath = settings.useTempPath
            tempPath = settings.tempPath
            preallocateAll = settings.preallocateAll ?? false
            cacheSizeMB = max(settings.cacheSizeMB ?? 0, 0)
            errorMessage = ""
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: languageManager.localized("Failed to load download settings: %@"),
                readableMessage(for: error)
            )
            showingErrorAlert = true
        } catch {
            errorMessage = String(
                format: languageManager.localized("Failed to load download settings: %@"),
                error.localizedDescription
            )
            showingErrorAlert = true
        }
    }

    private func saveSettings() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let settings = DownloadSettings(
                savePath: savePath,
                appendExtension: appendExtension,
                useTempPath: useTempPath,
                tempPath: tempPath,
                preallocateAll: server.type == .qBittorrent ? preallocateAll : nil,
                cacheSizeMB: server.type == .transmission ? max(cacheSizeMB, 0) : nil
            )
            try await appStateManager.saveDownloadSettings(settings, for: server)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            presentSaveToastAndDismiss()
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: languageManager.localized("Failed to save download settings: %@"),
                readableMessage(for: error)
            )
            showingErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            errorMessage = String(
                format: languageManager.localized("Failed to save download settings: %@"),
                error.localizedDescription
            )
            showingErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func presentSaveToastAndDismiss() {
        withAnimation {
            toastMessage = languageManager.localized("Download settings saved")
        }

        toastAutoHideTask?.cancel()
        toastAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func readableMessage(for error: TorrentClientError) -> String {
        switch error {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let wrapped):
            return wrapped.localizedDescription
        case .authenticationFailed:
            return "Authentication failed (401/403)"
        case .apiError(let message):
            return message
        case .decodingError:
            return "Unexpected API response format"
        }
    }
}
