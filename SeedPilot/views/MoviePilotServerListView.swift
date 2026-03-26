import SwiftUI

struct MoviePilotServerListView: View {
    private enum PresentedSheet: Identifiable {
        case add
        case edit(MoviePilotServerConfiguration)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let server):
                return "edit-\(server.id.uuidString)"
            }
        }
    }

    @State private var store = MoviePilotServerStore.shared
    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        Group {
            if store.servers.isEmpty {
                ContentUnavailableView(
                    LanguageManager.shared.localized("No servers configured"),
                    systemImage: "film.stack.fill",
                    description: Text(LanguageManager.shared.localized("Tap the top-right button to add your first MoviePilot server."))
                )
            } else {
                List {
                    Section {
                        ForEach(store.servers) { server in
                            Button {
                                presentedSheet = .edit(server)
                            } label: {
                                MoviePilotServerRow(server: server)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    presentedSheet = .edit(server)
                                } label: {
                                    Label(LanguageManager.shared.localized("Edit Server"), systemImage: "square.and.pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    store.delete(server)
                                } label: {
                                    Label(LanguageManager.shared.localized("Delete Server"), systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text(LanguageManager.shared.localized("Token is stored securely in Keychain on this device only."))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(LanguageManager.shared.localized("MoviePilot Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedSheet = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LanguageManager.shared.localized("Add Server"))
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .add:
                MoviePilotServerEditorSheet(server: nil, store: store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            case .edit(let server):
                MoviePilotServerEditorSheet(server: server, store: store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }
}

private struct MoviePilotServerRow: View {
    let server: MoviePilotServerConfiguration

    var body: some View {
        HStack(spacing: 12) {
            AppleStyleIcon(backgroundColor: .pink, systemName: "film.stack.fill")

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(server.baseURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct MoviePilotServerEditorSheet: View {
    private enum Field: Hashable {
        case name
        case url
        case token
    }

    @Environment(\.dismiss) private var dismiss
    let server: MoviePilotServerConfiguration?
    let store: MoviePilotServerStore

    @State private var viewModel: MoviePilotServerEditorViewModel
    @FocusState private var focusedField: Field?

    init(server: MoviePilotServerConfiguration?, store: MoviePilotServerStore) {
        self.server = server
        self.store = store
        _viewModel = State(
            initialValue: MoviePilotServerEditorViewModel(
                server: server,
                storedToken: server.flatMap { store.token(for: $0.id) }
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AppleStyleIcon(backgroundColor: .purple, systemName: "tag.fill")
                        TextField(LanguageManager.shared.localized("Name"), text: $viewModel.name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit {
                                focusedField = .url
                            }
                    }

                    HStack(spacing: 12) {
                        AppleStyleIcon(backgroundColor: .blue, systemName: "network")
                        TextField(LanguageManager.shared.localized("URL"), text: $viewModel.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .url)
                            .onSubmit {
                                focusedField = .token
                            }
                    }
                } header: {
                    Text(LanguageManager.shared.localized("MoviePilot Server"))
                } footer: {
                    Text(LanguageManager.shared.localized("The URL must include http:// or https://."))
                }

                Section {
                    HStack(spacing: 12) {
                        AppleStyleIcon(backgroundColor: .indigo, systemName: "key.fill")

                        Group {
                            if viewModel.isTokenVisible {
                                TextField(LanguageManager.shared.localized("Token"), text: $viewModel.token)
                            } else {
                                SecureField(LanguageManager.shared.localized("Token"), text: $viewModel.token)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .token)

                        Button {
                            viewModel.isTokenVisible.toggle()
                        } label: {
                            Image(systemName: viewModel.isTokenVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.hasStoredToken {
                        Text(LanguageManager.shared.localized("Leave blank to keep the current token."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Authentication"))
                }

                Section {
                    Button {
                        Task {
                            await viewModel.testConnection()
                        }
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            if viewModel.isTestingConnection {
                                ProgressView()
                            } else {
                                Text(LanguageManager.shared.localized("Test Connection"))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .disabled(!viewModel.canTestConnection)
                    .foregroundStyle(.blue)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                        dimensions.width
                    }

                    if let result = viewModel.testResult {
                        HStack(spacing: 8) {
                            Image(systemName: result.icon)
                                .foregroundStyle(result.color)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(result.color)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(
                LanguageManager.shared.localized(server == nil ? "Add Server" : "Edit Server")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Save")) {
                        viewModel.save(to: store)
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .onChange(of: viewModel.url) { _, _ in
                viewModel.clearTestResult()
            }
            .onChange(of: viewModel.token) { _, _ in
                viewModel.clearTestResult()
            }
        }
    }
}

private extension MoviePilotServerEditorViewModel.TestResult {
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var message: String {
        switch self {
        case .success(let message), .failure(let message):
            return message
        }
    }
}

#Preview {
    NavigationStack {
        MoviePilotServerListView()
    }
}
