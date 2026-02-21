import SwiftUI

struct PresetPathsView: View {
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    @State private var showingAddAlert = false
    @State private var editingOriginalPath: String?
    @State private var newPath = ""

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    private var canAddNewPath: Bool {
        !newPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEditingPath: Bool {
        editingOriginalPath != nil
    }

    var body: some View {
        Group {
            if presetSavePaths.isEmpty {
                ContentUnavailableView(
                    LanguageManager.shared.localized("No Preset Save Paths"),
                    systemImage: "folder",
                    description: Text(LanguageManager.shared.localized("Add preset paths to quickly fill save directories."))
                )
            } else {
                List {
                    ForEach(presetSavePaths, id: \.self) { path in
                        Text(path)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingOriginalPath = path
                                    newPath = path
                                    showingAddAlert = true
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    deletePath(path)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(LanguageManager.shared.localized("Preset Save Paths"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingOriginalPath = nil
                    newPath = ""
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LanguageManager.shared.localized("Add Path"))
            }
        }
        .alert(
            LanguageManager.shared.localized(isEditingPath ? "Edit" : "Add Path"),
            isPresented: $showingAddAlert
        ) {
            TextField(LanguageManager.shared.localized("Path"), text: $newPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {
                newPath = ""
                editingOriginalPath = nil
            }
            Button(LanguageManager.shared.localized("Save")) {
                savePath()
            }
            .disabled(!canAddNewPath)
        }
    }

    private func savePath() {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = presetSavePaths
        if let original = editingOriginalPath, let index = updated.firstIndex(of: original) {
            updated[index] = trimmed
        } else {
            updated.append(trimmed)
        }
        presetSavePathsRaw = PresetSavePathsCodec.encode(updated)
        newPath = ""
        editingOriginalPath = nil
    }

    private func deletePath(_ path: String) {
        var updated = presetSavePaths
        updated.removeAll { $0 == path }
        presetSavePathsRaw = PresetSavePathsCodec.encode(updated)
    }
}

#Preview {
    NavigationStack {
        PresetPathsView()
    }
}
