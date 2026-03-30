//
//  AddTorrentView.swift
//  OiiQT
//
//  Created by gangz1o on 2026/2/15.
//
import SwiftUI
import UniformTypeIdentifiers

struct AddTorrentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appStateManager

    // Mode
    enum InputMode: String, CaseIterable {
        case link
        case file

        var localizedTitle: String {
            switch self {
            case .link:
                return LanguageManager.shared.localized("Links")
            case .file:
                return LanguageManager.shared.localized("File")
            }
        }
    }
    @State private var inputMode: InputMode = .link

    // Inputs
    @State private var magnetLinks: String = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""

    // Options
    @State private var options = AddTorrentOptions()
    @State private var tagsString: String = "" // For binding to comma-separated text
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    // State
    @State private var isAdding = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Input Mode
                Section {
                    Picker(LanguageManager.shared.localized("Input Mode"), selection: $inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .padding()
                }

                // Section 2: Content
                Section {
                    if inputMode == .link {
                        TextEditor(text: $magnetLinks)
                            .frame(minHeight: 120)
                            .overlay(
                                Group {
                                    if magnetLinks.isEmpty {
                                        Text(LanguageManager.shared.localized("Paste magnet links or HTTP/HTTPS links here, one per line"))
                                            .foregroundColor(.gray.opacity(0.6))
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                    }
                                },
                                alignment: .topLeading
                            )
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(selectedFileName.isEmpty ? LanguageManager.shared.localized("Select .torrent File") : selectedFileName)
                                        .foregroundStyle(selectedFileName.isEmpty ? .primary : .primary)
                                    if !selectedFileName.isEmpty {
                                        Text(LanguageManager.shared.localized("Tap to Replace"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text(inputMode == .link ? LanguageManager.shared.localized("Link List") : LanguageManager.shared.localized("Torrent File"))
                }

                // Section 3: Options
                Section(LanguageManager.shared.localized("Configuration")) {
                    HStack {
                        Text(LanguageManager.shared.localized("Save Path"))
                        Spacer()
                        HStack(spacing: 8) {
                            TextField(LanguageManager.shared.localized("Default"), text: $options.savePath)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            Menu {
                                if presetSavePaths.isEmpty {
                                    Text(LanguageManager.shared.localized("No Preset Save Paths"))
                                } else {
                                    ForEach(presetSavePaths, id: \.self) { path in
                                        Button(path) {
                                            options.savePath = path
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    HStack {
                        Text(LanguageManager.shared.localized("Category"))
                        Spacer()
                        TextField(LanguageManager.shared.localized("Optional"), text: $options.category)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text(LanguageManager.shared.localized("Tags"))
                        Spacer()
                         TextField(LanguageManager.shared.localized("Comma separated"), text: $tagsString)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: tagsString) { oldValue, newValue in
                                options.tags = newValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            }
                    }
                }

                // Section 4: Flags
                Section {
                    Toggle(LanguageManager.shared.localized("Auto Start"), isOn: Binding(
                        get: { !options.isPaused },
                        set: { options.isPaused = !$0 }
                    ))

                    Toggle(LanguageManager.shared.localized("Skip Hash Check"), isOn: $options.skipHashCheck)

                    Toggle(LanguageManager.shared.localized("Sequential Download"), isOn: $options.isSequential)
                } header: {
                    Text(LanguageManager.shared.localized("Status"))
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Add Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addTasks()
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text(LanguageManager.shared.localized("Add"))
                                .bold()
                        }
                    }
                    .disabled(isAdding || (inputMode == .link && magnetLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (inputMode == .file && selectedFileURL == nil))
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item], // UTType.item includes roughly everything, verifying extension manually is safer or use .data
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Security Note: In SwiftUI fileImporter, we usually get security scoped URL.
                    // We must prepare to access it.
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        // Copy to tmp or read data immediately?
                        // Better to keep URL and read on submit, but we need to ensure access persists or just read metadata now.
                        selectedFileName = url.lastPathComponent
                        // We will store the URL but we might need to handle security scope again when reading.
                        // Actually, for simplicity, let's copy it to a temp location we control.
                        do {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.removeItem(at: tempURL)
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            selectedFileURL = tempURL
                        } catch {
                            print("File copy error: \(error)")
                            errorMessage = String(format: LanguageManager.shared.localized("Failed to read file: %@"), error.localizedDescription)
                            showError = true
                        }
                    } else {
                        // Access denied
                        errorMessage = LanguageManager.shared.localized("Unable to access the selected file")
                        showError = true
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .alert(LanguageManager.shared.localized("Error"), isPresented: $showError) {
                Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? LanguageManager.shared.localized("Unknown Error"))
            }
        }
    }

    private func addTasks() {
        isAdding = true

        Task {
            do {
                if inputMode == .link {
                    // Split by newlines and filter valid links
                    let links = magnetLinks.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    if !links.isEmpty {
                        // qBittorrent API 'urls' parameter accepts both magnet: and http:// links
                        // mixed in the same request (separated by \n), so we can send them all at once.
                        try await appStateManager.addTorrents(links, options: options)
                    }
                } else if let url = selectedFileURL {
                    try await appStateManager.addTorrentFile(url, options: options)
                }

                await MainActor.run {
                    isAdding = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    errorMessage = String(format: LanguageManager.shared.localized("Add failed: %@"), error.localizedDescription)
                    showError = true
                }
            }
        }
    }
}

#Preview {
    AddTorrentView()
        .environment(AppStateManager())
}
