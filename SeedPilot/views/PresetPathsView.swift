import SwiftUI

struct PresetPathsView: View {
    @AppStorage("presetSavePaths") private var presetSavePathsRaw: String = "[]"

    @State private var showingAddAlert = false
    @State private var newPath = ""

    private var presetSavePaths: [String] {
        PresetSavePathsCodec.decode(presetSavePathsRaw)
    }

    private var canAddNewPath: Bool {
        !newPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    }
                    .onDelete(perform: deletePaths)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(LanguageManager.shared.localized("Preset Save Paths"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LanguageManager.shared.localized("Add Path"))
            }
        }
        .alert(LanguageManager.shared.localized("Add Path"), isPresented: $showingAddAlert) {
            TextField(LanguageManager.shared.localized("Path"), text: $newPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {
                newPath = ""
            }
            Button(LanguageManager.shared.localized("Save")) {
                addPath()
            }
            .disabled(!canAddNewPath)
        }
    }

    private func addPath() {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = presetSavePaths
        updated.append(trimmed)
        presetSavePathsRaw = PresetSavePathsCodec.encode(updated)
        newPath = ""
    }

    private func deletePaths(at offsets: IndexSet) {
        var updated = presetSavePaths
        updated.remove(atOffsets: offsets)
        presetSavePathsRaw = PresetSavePathsCodec.encode(updated)
    }
}

#Preview {
    NavigationStack {
        PresetPathsView()
    }
}
