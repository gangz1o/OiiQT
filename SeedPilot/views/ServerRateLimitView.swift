import SwiftUI
import Combine

struct ServerRateLimitView: View {
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig

    @StateObject private var viewModel: ServerRateLimitViewModel
    @State private var showingErrorAlert = false

    init(server: ServerConfig) {
        self.server = server
        _viewModel = StateObject(wrappedValue: ServerRateLimitViewModel(server: server))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    limitToggleRow(
                        titleKey: "Download",
                        isOn: $viewModel.settings.globalDownloadEnabled,
                        value: $viewModel.settings.globalDownloadKBps
                    )

                    limitToggleRow(
                        titleKey: "Upload",
                        isOn: $viewModel.settings.globalUploadEnabled,
                        value: $viewModel.settings.globalUploadKBps
                    )
                } header: {
                    Text(LanguageManager.shared.localized("Global Speed Limits"))
                } footer: {
                    if viewModel.isQBTransferOnlyMode {
                        Text(LanguageManager.shared.localized("Limited by qB permissions: only global upload/download limits are available."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if viewModel.supportsAdvancedQBControls {
                    Section {
                        Toggle(isOn: $viewModel.settings.alternativeEnabled.animation()) {
                            HStack(spacing: 12) {
                                RateLimitIconBadge(systemName: "tortoise.fill", tint: .blue)
                                Text(LanguageManager.shared.localized("Enable Alternative Limits"))
                            }
                        }

                        if viewModel.settings.alternativeEnabled {
                            limitToggleRow(
                                titleKey: "Download",
                                isOn: $viewModel.settings.alternativeDownloadEnabled,
                                value: $viewModel.settings.alternativeDownloadKBps
                            )

                            limitToggleRow(
                                titleKey: "Upload",
                                isOn: $viewModel.settings.alternativeUploadEnabled,
                                value: $viewModel.settings.alternativeUploadKBps
                            )
                        }
                    } header: {
                        Text(LanguageManager.shared.localized("Alternative Rate Limits"))
                    }

                    Section {
                        Toggle(isOn: $viewModel.settings.scheduleEnabled.animation()) {
                            Text(LanguageManager.shared.localized("Enable Scheduled Alternative Limits"))
                        }
                        .disabled(!viewModel.settings.alternativeEnabled)

                        if viewModel.settings.scheduleEnabled && viewModel.settings.alternativeEnabled {
                            DatePicker(
                                LanguageManager.shared.localized("Start Time"),
                                selection: timeBinding(\.scheduleStartMinutes),
                                displayedComponents: .hourAndMinute
                            )

                            DatePicker(
                                LanguageManager.shared.localized("End Time"),
                                selection: timeBinding(\.scheduleEndMinutes),
                                displayedComponents: .hourAndMinute
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text(LanguageManager.shared.localized("Weekdays"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 6) {
                                    ForEach(Array(weekdayItems.enumerated()), id: \.offset) { index, item in
                                        weekdayChip(index: index, label: item)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(LanguageManager.shared.localized("Scheduled Alternative Limits"))
                    }
                }
            }
            .disabled(viewModel.isLoading || viewModel.isSaving)
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color(uiColor: .systemBackground).opacity(0.9)
                        ProgressView(LanguageManager.shared.localized("Loading..."))
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Rate Limit Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(LanguageManager.shared.localized("Save")) {
                            Task {
                                let saved = await viewModel.save()
                                if saved {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    dismiss()
                                } else {
                                    showingErrorAlert = true
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await viewModel.load()
                if !viewModel.errorMessage.isEmpty {
                    showingErrorAlert = true
                }
            }
            .alert(LanguageManager.shared.localized("Rate Limit Settings"), isPresented: $showingErrorAlert) {
                Button(LanguageManager.shared.localized("OK"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var weekdayItems: [String] {
        [
            LanguageManager.shared.localized("Sun"),
            LanguageManager.shared.localized("Mon"),
            LanguageManager.shared.localized("Tue"),
            LanguageManager.shared.localized("Wed"),
            LanguageManager.shared.localized("Thu"),
            LanguageManager.shared.localized("Fri"),
            LanguageManager.shared.localized("Sat")
        ]
    }

    private func limitToggleRow(titleKey: String, isOn: Binding<Bool>, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(LanguageManager.shared.localized(titleKey), isOn: isOn.animation())

            if isOn.wrappedValue {
                HStack(spacing: 10) {
                    TextField(
                        LanguageManager.shared.localized("Unlimited"),
                        value: value,
                        format: .number
                    )
                    .keyboardType(.numberPad)

                    Spacer(minLength: 6)

                    Text(LanguageManager.shared.localized("KB/s"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func weekdayChip(index: Int, label: String) -> some View {
        let selected = viewModel.settings.scheduleWeekdays.contains(index)

        return Button {
            if selected {
                viewModel.settings.scheduleWeekdays.remove(index)
                if viewModel.settings.scheduleWeekdays.isEmpty {
                    viewModel.settings.scheduleWeekdays.insert(index)
                }
            } else {
                viewModel.settings.scheduleWeekdays.insert(index)
            }
        } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                )
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<RateLimitSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = RateLimitSettings.clampedMinute(viewModel.settings[keyPath: keyPath])
                let calendar = Calendar.current
                let base = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: minutes, to: base) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let hour = components.hour ?? 0
                let minute = components.minute ?? 0
                viewModel.settings[keyPath: keyPath] = RateLimitSettings.clampedMinute(hour * 60 + minute)
            }
        )
    }
}

@MainActor
final class ServerRateLimitViewModel: ObservableObject {
    @Published var settings = RateLimitSettings()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage = ""
    @Published private(set) var capability: RateLimitCapability = .full

    private let server: ServerConfig

    init(server: ServerConfig) {
        self.server = server
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await ServerRateLimitManager.shared.load(for: server)
            settings = result.settings
            capability = result.capability
            errorMessage = ""
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: LanguageManager.shared.localized("Failed to load rate limit settings: %@"),
                readableMessage(for: error)
            )
        } catch {
            errorMessage = String(
                format: LanguageManager.shared.localized("Failed to load rate limit settings: %@"),
                error.localizedDescription
            )
        }
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        do {
            try await ServerRateLimitManager.shared.save(settings, for: server, capability: capability)
            errorMessage = ""
            return true
        } catch let error as TorrentClientError {
            errorMessage = String(
                format: LanguageManager.shared.localized("Failed to save rate limit settings: %@"),
                readableMessage(for: error)
            )
            return false
        } catch {
            errorMessage = String(
                format: LanguageManager.shared.localized("Failed to save rate limit settings: %@"),
                error.localizedDescription
            )
            return false
        }
    }

    var supportsAdvancedQBControls: Bool {
        capability.supportsAdvancedQBControls
    }

    var isQBTransferOnlyMode: Bool {
        capability == .qbTransferOnly
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

private struct RateLimitIconBadge: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.96), tint.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolVariant(.fill)
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}
