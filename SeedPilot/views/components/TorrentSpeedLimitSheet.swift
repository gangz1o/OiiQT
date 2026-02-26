import SwiftUI

struct TorrentSpeedLimitSheet: View {
    let task: TorrentTask
    let appStateManager: AppStateManager

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var dlLimitText = ""
    @State private var upLimitText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                            Spacer()
                        }
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                } else {
                    Section {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.blue)
                            Text(languageManager.localized("Download Limit"))
                            Spacer()
                            TextField("0", text: $dlLimitText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("KB/s")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.green)
                            Text(languageManager.localized("Upload Limit"))
                            Spacer()
                            TextField("0", text: $upLimitText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text("KB/s")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(languageManager.localized("Speed Limit"))
                    } footer: {
                        Text(languageManager.localized("Set to 0 to remove the limit."))
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(languageManager.localized("Speed Limit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(languageManager.localized("Save")) {
                            saveSpeedLimits()
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .alert(languageManager.localized("Error"), isPresented: $showingError) {
                Button(languageManager.localized("OK"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await loadCurrentLimits()
        }
    }

    private func loadCurrentLimits() async {
        isLoading = true
        do {
            let limits = try await appStateManager.fetchTorrentSpeedLimits(for: task)
            dlLimitText = limits.dlKBps > 0 ? "\(limits.dlKBps)" : "0"
            upLimitText = limits.upKBps > 0 ? "\(limits.upKBps)" : "0"
        } catch {
            errorMessage = languageManager.localized("Failed to load speed limits")
            showingError = true
            dlLimitText = "0"
            upLimitText = "0"
        }
        isLoading = false
    }

    private func saveSpeedLimits() {
        let dlKBps = max(0, Int(dlLimitText) ?? 0)
        let upKBps = max(0, Int(upLimitText) ?? 0)
        isSaving = true

        Task {
            do {
                try await appStateManager.setTorrentSpeedLimits(for: task, dlKBps: dlKBps, upKBps: upKBps)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = languageManager.localized("Failed to save speed limits")
                showingError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isSaving = false
        }
    }
}
