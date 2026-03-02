import SwiftUI
import UIKit

struct ConnectionSettingsView: View {
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

    @State private var listenPortText = "0"
    @State private var useUPnP = false
    @State private var selectedProtocol = 0

    @State private var globalConnectionsLimited = false
    @State private var globalConnectionsText = "0"
    @State private var perTorrentConnectionsLimited = false
    @State private var perTorrentConnectionsText = "0"

    @State private var globalUploadsLimited = false
    @State private var globalUploadsText = "0"
    @State private var perTorrentUploadsLimited = false
    @State private var perTorrentUploadsText = "0"

    @State private var qbTorrentQueueEnabled = false
    @State private var qbMaxActiveDownloadsText = "0"
    @State private var qbMaxActiveUploadsText = "0"
    @State private var qbMaxActiveTorrentsText = "0"

    @State private var trDownloadQueueEnabled = false
    @State private var trDownloadQueueSizeText = "0"
    @State private var trSeedQueueEnabled = false
    @State private var trSeedQueueSizeText = "0"
    @State private var trQueueStalledEnabled = false
    @State private var trQueueStalledMinutesText = "0"

    private var supportsUploadSlots: Bool {
        server.type != .transmission
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        languageManager.localized("Peer Connection Protocol"),
                        selection: $selectedProtocol
                    ) {
                        Text(languageManager.localized("TCP and μTP")).tag(0)
                        Text(languageManager.localized("TCP")).tag(1)
                        Text(languageManager.localized("μTP")).tag(2)
                    }
                    .pickerStyle(.menu)
                }

                Section(languageManager.localized("Listening Port")) {
                    HStack(spacing: 10) {
                        Text(languageManager.localized("Incoming Port"))
                        Spacer(minLength: 8)
                        TextField("0", text: $listenPortText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Button(languageManager.localized("Random")) {
                            randomizePort()
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle(
                        languageManager.localized("Use UPnP / NAT-PMP port forwarding"),
                        isOn: $useUPnP
                    )
                }

                Section(languageManager.localized("Connection Limits")) {
                    limitToggleRow(
                        titleKey: "Global Maximum Connections",
                        isOn: $globalConnectionsLimited,
                        text: $globalConnectionsText
                    )
                    limitToggleRow(
                        titleKey: "Per Torrent Maximum Connections",
                        isOn: $perTorrentConnectionsLimited,
                        text: $perTorrentConnectionsText
                    )

                    if supportsUploadSlots {
                        limitToggleRow(
                            titleKey: "Global Upload Slots",
                            isOn: $globalUploadsLimited,
                            text: $globalUploadsText
                        )
                        limitToggleRow(
                            titleKey: "Per Torrent Upload Slots",
                            isOn: $perTorrentUploadsLimited,
                            text: $perTorrentUploadsText
                        )
                    }
                }

                Section(languageManager.localized("Torrent Queue")) {
                    if server.type == .qBittorrent {
                        Toggle(languageManager.localized("Enable Torrent Queueing"), isOn: $qbTorrentQueueEnabled.animation())

                        if qbTorrentQueueEnabled {
                            numberInputRow(
                                titleKey: "Maximum active downloads",
                                text: $qbMaxActiveDownloadsText
                            )

                            numberInputRow(
                                titleKey: "Maximum active uploads",
                                text: $qbMaxActiveUploadsText
                            )

                            numberInputRow(
                                titleKey: "Maximum active torrents",
                                text: $qbMaxActiveTorrentsText
                            )
                        }
                    } else {
                        queueToggleInputRow(
                            titleKey: "Enable download queue",
                            valueTitleKey: "Maximum simultaneous downloads",
                            isOn: $trDownloadQueueEnabled,
                            text: $trDownloadQueueSizeText
                        )

                        queueToggleInputRow(
                            titleKey: "Enable upload queue",
                            valueTitleKey: "Maximum simultaneous uploads",
                            isOn: $trSeedQueueEnabled,
                            text: $trSeedQueueSizeText
                        )

                        queueToggleInputRow(
                            titleKey: "Consider torrent stalled after no activity",
                            valueTitleKey: "Minutes",
                            isOn: $trQueueStalledEnabled,
                            text: $trQueueStalledMinutesText,
                            useValueTitleAsUnit: true
                        )
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
            .navigationTitle(languageManager.localized("Connection Settings"))
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

    private func limitToggleRow(titleKey: String, isOn: Binding<Bool>, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(languageManager.localized(titleKey), isOn: isOn.animation())

            if isOn.wrappedValue {
                TextField(
                    languageManager.localized("Unlimited"),
                    text: text
                )
                .keyboardType(.numberPad)
            }
        }
        .padding(.vertical, 2)
    }

    private func numberInputRow(titleKey: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(languageManager.localized(titleKey))
            Spacer(minLength: 8)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func queueToggleInputRow(
        titleKey: String,
        valueTitleKey: String,
        isOn: Binding<Bool>,
        text: Binding<String>,
        useValueTitleAsUnit: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(languageManager.localized(titleKey), isOn: isOn.animation())

            if isOn.wrappedValue {
                HStack(spacing: 10) {
                    if !useValueTitleAsUnit {
                        Text(languageManager.localized(valueTitleKey))
                    }

                    TextField("0", text: text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)

                    if useValueTitleAsUnit {
                        Text(languageManager.localized(valueTitleKey))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func randomizePort() {
        listenPortText = String(Int.random(in: 1024...65535))
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let settings = try await appStateManager.fetchConnectionSettings(for: server)
            apply(settings: settings)
            errorMessage = ""
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: languageManager.localized("Failed to load connection settings: %@"),
                readableMessage(for: error)
            )
            showingErrorAlert = true
        } catch {
            errorMessage = String(
                format: languageManager.localized("Failed to load connection settings: %@"),
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
            let settings = buildSettings()
            try await appStateManager.saveConnectionSettings(settings, for: server)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            presentSaveToastAndDismiss()
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: languageManager.localized("Failed to save connection settings: %@"),
                readableMessage(for: error)
            )
            showingErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            errorMessage = String(
                format: languageManager.localized("Failed to save connection settings: %@"),
                error.localizedDescription
            )
            showingErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func apply(settings: ConnectionSettings) {
        listenPortText = "\(max(settings.listenPort, 0))"
        useUPnP = settings.useUPnP
        selectedProtocol = min(max(settings.bittorrentProtocol, 0), 2)

        globalConnectionsLimited = settings.maxConnections > 0
        globalConnectionsText = "\(max(settings.maxConnections, 0))"

        perTorrentConnectionsLimited = settings.maxConnectionsPerTorrent > 0
        perTorrentConnectionsText = "\(max(settings.maxConnectionsPerTorrent, 0))"

        if let maxUploads = settings.maxUploads {
            globalUploadsLimited = maxUploads > 0
            globalUploadsText = "\(max(maxUploads, 0))"
        } else {
            globalUploadsLimited = false
            globalUploadsText = "0"
        }

        if let maxUploadsPerTorrent = settings.maxUploadsPerTorrent {
            perTorrentUploadsLimited = maxUploadsPerTorrent > 0
            perTorrentUploadsText = "\(max(maxUploadsPerTorrent, 0))"
        } else {
            perTorrentUploadsLimited = false
            perTorrentUploadsText = "0"
        }

        qbTorrentQueueEnabled = settings.torrentQueueEnabled ?? false
        qbMaxActiveDownloadsText = "\(max(settings.maxActiveDownloads ?? 0, 0))"
        qbMaxActiveUploadsText = "\(max(settings.maxActiveUploads ?? 0, 0))"
        qbMaxActiveTorrentsText = "\(max(settings.maxActiveTorrents ?? 0, 0))"

        trDownloadQueueEnabled = settings.downloadQueueEnabled ?? false
        trDownloadQueueSizeText = "\(max(settings.downloadQueueSize ?? 0, 0))"
        trSeedQueueEnabled = settings.seedQueueEnabled ?? false
        trSeedQueueSizeText = "\(max(settings.seedQueueSize ?? 0, 0))"
        trQueueStalledEnabled = settings.queueStalledEnabled ?? false
        trQueueStalledMinutesText = "\(max(settings.queueStalledMinutes ?? 0, 0))"
    }

    private func buildSettings() -> ConnectionSettings {
        let listenPort = min(max(Int(listenPortText) ?? 6881, 1), 65535)
        let protocolValue = min(max(selectedProtocol, 0), 2)

        let maxConnections = globalConnectionsLimited ? max(Int(globalConnectionsText) ?? 0, 0) : 0
        let maxConnectionsPerTorrent = perTorrentConnectionsLimited ? max(Int(perTorrentConnectionsText) ?? 0, 0) : 0

        let maxUploads: Int? = supportsUploadSlots
            ? (globalUploadsLimited ? max(Int(globalUploadsText) ?? 0, 0) : 0)
            : nil
        let maxUploadsPerTorrent: Int? = supportsUploadSlots
            ? (perTorrentUploadsLimited ? max(Int(perTorrentUploadsText) ?? 0, 0) : 0)
            : nil

        let qbQueueEnabled = server.type == .qBittorrent ? qbTorrentQueueEnabled : nil
        let qbMaxActiveDownloads = server.type == .qBittorrent ? max(Int(qbMaxActiveDownloadsText) ?? 0, 0) : nil
        let qbMaxActiveUploads = server.type == .qBittorrent ? max(Int(qbMaxActiveUploadsText) ?? 0, 0) : nil
        let qbMaxActiveTorrents = server.type == .qBittorrent ? max(Int(qbMaxActiveTorrentsText) ?? 0, 0) : nil

        let trDownQueueEnabled = server.type == .transmission ? trDownloadQueueEnabled : nil
        let trDownQueueSize = server.type == .transmission ? max(Int(trDownloadQueueSizeText) ?? 0, 0) : nil
        let trSeedQueueEnabledValue = server.type == .transmission ? trSeedQueueEnabled : nil
        let trSeedQueueSizeValue = server.type == .transmission ? max(Int(trSeedQueueSizeText) ?? 0, 0) : nil
        let trStalledEnabled = server.type == .transmission ? trQueueStalledEnabled : nil
        let trStalledMinutes = server.type == .transmission ? max(Int(trQueueStalledMinutesText) ?? 0, 0) : nil

        return ConnectionSettings(
            listenPort: listenPort,
            useUPnP: useUPnP,
            maxConnections: maxConnections,
            maxConnectionsPerTorrent: maxConnectionsPerTorrent,
            maxUploads: maxUploads,
            maxUploadsPerTorrent: maxUploadsPerTorrent,
            bittorrentProtocol: protocolValue,
            torrentQueueEnabled: qbQueueEnabled,
            maxActiveDownloads: qbMaxActiveDownloads,
            maxActiveUploads: qbMaxActiveUploads,
            maxActiveTorrents: qbMaxActiveTorrents,
            downloadQueueEnabled: trDownQueueEnabled,
            downloadQueueSize: trDownQueueSize,
            seedQueueEnabled: trSeedQueueEnabledValue,
            seedQueueSize: trSeedQueueSizeValue,
            queueStalledEnabled: trStalledEnabled,
            queueStalledMinutes: trStalledMinutes
        )
    }

    private func presentSaveToastAndDismiss() {
        withAnimation {
            toastMessage = languageManager.localized("Connection settings saved")
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
