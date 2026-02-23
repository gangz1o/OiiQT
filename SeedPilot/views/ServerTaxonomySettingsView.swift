import SwiftUI

struct ServerTaxonomySettingsView: View {
    let server: ServerConfig

    @Environment(AppStateManager.self) private var appStateManager

    @State private var categories: [QBittorrentClient.ServerCategoryEntry] = []
    @State private var tags: [String] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false

    @State private var categoryDraft: CategoryDraft?
    @State private var tagDraft: TagDraft?
    @State private var pendingDeleteCategory: QBittorrentClient.ServerCategoryEntry?
    @State private var pendingDeleteTag: TagDeleteTarget?

    private var supportsCategories: Bool {
        server.type == .qBittorrent
    }

    private var titleKey: String {
        supportsCategories ? "Category & Tags Settings" : "Tag Settings"
    }

    var body: some View {
        List {
            if supportsCategories {
                Section(LanguageManager.shared.localized("Category")) {
                    if categories.isEmpty && !isLoading {
                        Text(LanguageManager.shared.localized("No Categories"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(categories) { category in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !category.savePath.isEmpty {
                                    Text(category.savePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    categoryDraft = CategoryDraft(
                                        originalName: category.name,
                                        name: category.name,
                                        savePath: category.savePath
                                    )
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    pendingDeleteCategory = category
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }

            Section(LanguageManager.shared.localized("Tags")) {
                if tags.isEmpty && !isLoading {
                    Text(LanguageManager.shared.localized("No Tags"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    tagDraft = TagDraft(originalName: tag, name: tag)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    pendingDeleteTag = TagDeleteTarget(name: tag)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if isLoading && categories.isEmpty && tags.isEmpty {
                ProgressView(LanguageManager.shared.localized("Loading..."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LanguageManager.shared.localized(titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if supportsCategories {
                        Button(LanguageManager.shared.localized("Add Category")) {
                            categoryDraft = CategoryDraft(originalName: nil, name: "", savePath: "")
                        }
                    }

                    Button(LanguageManager.shared.localized("Add Tag")) {
                        tagDraft = TagDraft(originalName: nil, name: "")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task(id: server.id) {
            await reloadData()
        }
        .refreshable {
            await reloadData()
        }
        .sheet(item: $categoryDraft) { draft in
            CategoryEditorSheet(draft: draft) { submitted in
                Task {
                    await submitCategoryDraft(submitted)
                }
            }
        }
        .sheet(item: $tagDraft) { draft in
            TagEditorSheet(draft: draft) { submitted in
                Task {
                    await submitTagDraft(submitted)
                }
            }
        }
        .alert(LanguageManager.shared.localized("Delete Category"), isPresented: deleteCategoryDialogBinding) {
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {}
            Button(LanguageManager.shared.localized("Delete"), role: .destructive) {
                guard let target = pendingDeleteCategory else { return }
                Task {
                    await deleteCategory(target)
                }
            }
        } message: {
            if let target = pendingDeleteCategory {
                Text(String(format: LanguageManager.shared.localized("Are you sure you want to delete %@?"), target.name))
            }
        }
        .alert(LanguageManager.shared.localized("Delete Tag"), isPresented: deleteTagDialogBinding) {
            Button(LanguageManager.shared.localized("Cancel"), role: .cancel) {}
            Button(LanguageManager.shared.localized("Delete"), role: .destructive) {
                guard let target = pendingDeleteTag else { return }
                Task {
                    await deleteTag(target.name)
                }
            }
        } message: {
            if let target = pendingDeleteTag {
                Text(String(format: LanguageManager.shared.localized("Are you sure you want to delete %@?"), target.name))
            }
        }
        .alert(LanguageManager.shared.localized("Error"), isPresented: $showingErrorAlert) {
            Button(LanguageManager.shared.localized("OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var deleteCategoryDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { showing in
                if !showing {
                    pendingDeleteCategory = nil
                }
            }
        )
    }

    private var deleteTagDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTag != nil },
            set: { showing in
                if !showing {
                    pendingDeleteTag = nil
                }
            }
        )
    }

    private func reloadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if supportsCategories {
                categories = try await appStateManager.fetchServerCategories(for: server)
            } else {
                categories = []
            }
            tags = try await appStateManager.fetchServerTags(for: server)
        } catch {
            showError(error)
        }
    }

    private func submitCategoryDraft(_ draft: CategoryDraft) async {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            if let originalName = draft.originalName {
                try await appStateManager.updateServerCategory(
                    for: server,
                    oldName: originalName,
                    newName: trimmedName,
                    savePath: draft.savePath
                )
            } else {
                try await appStateManager.createServerCategory(
                    for: server,
                    name: trimmedName,
                    savePath: draft.savePath
                )
            }
            await reloadData()
        } catch {
            showError(error)
        }
    }

    private func submitTagDraft(_ draft: TagDraft) async {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            if let originalName = draft.originalName {
                try await appStateManager.updateServerTag(
                    for: server,
                    oldName: originalName,
                    newName: trimmedName
                )
            } else {
                try await appStateManager.createServerTag(
                    for: server,
                    name: trimmedName
                )
            }
            await reloadData()
        } catch {
            showError(error)
        }
    }

    private func deleteCategory(_ category: QBittorrentClient.ServerCategoryEntry) async {
        pendingDeleteCategory = nil
        do {
            try await appStateManager.deleteServerCategory(for: server, name: category.name)
            await reloadData()
        } catch {
            showError(error)
        }
    }

    private func deleteTag(_ tag: String) async {
        pendingDeleteTag = nil
        do {
            try await appStateManager.deleteServerTag(for: server, name: tag)
            await reloadData()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = (error as? TorrentClientError).flatMap { mappedError in
            switch mappedError {
            case .apiError(let message):
                return LanguageManager.shared.localized(message)
            default:
                return nil
            }
        } ?? error.localizedDescription
        showingErrorAlert = true
    }
}

private struct CategoryDraft: Identifiable {
    let id = UUID()
    let originalName: String?
    var name: String
    var savePath: String
}

private struct TagDraft: Identifiable {
    let id = UUID()
    let originalName: String?
    var name: String
}

private struct TagDeleteTarget: Identifiable {
    let name: String

    var id: String { name }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var name: String
    @State private var savePath: String

    let draft: CategoryDraft
    let onSubmit: (CategoryDraft) -> Void

    init(draft: CategoryDraft, onSubmit: @escaping (CategoryDraft) -> Void) {
        self.draft = draft
        self.onSubmit = onSubmit
        _name = State(initialValue: draft.name)
        _savePath = State(initialValue: draft.savePath)
    }

    private var titleKey: String {
        draft.originalName == nil ? "Add Category" : "Edit Category"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(languageManager.localized("Category Name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(languageManager.localized("Save Path (Optional)"), text: $savePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(languageManager.localized(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Save")) {
                        onSubmit(
                            CategoryDraft(
                                originalName: draft.originalName,
                                name: name,
                                savePath: savePath
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var name: String

    let draft: TagDraft
    let onSubmit: (TagDraft) -> Void

    init(draft: TagDraft, onSubmit: @escaping (TagDraft) -> Void) {
        self.draft = draft
        self.onSubmit = onSubmit
        _name = State(initialValue: draft.name)
    }

    private var titleKey: String {
        draft.originalName == nil ? "Add Tag" : "Edit Tag"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(languageManager.localized("Tag Name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(languageManager.localized(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Save")) {
                        onSubmit(
                            TagDraft(
                                originalName: draft.originalName,
                                name: name
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
