import SwiftUI

struct TrackerAliasListView: View {
    @ObservedObject private var aliasManager = TrackerAliasManager.shared
    @State private var showingAddSheet = false
    @State private var editingRule: TrackerAliasRule?

    var body: some View {
        Group {
            if aliasManager.rules.isEmpty {
                ContentUnavailableView(
                    LanguageManager.shared.localized("No Tracker Aliases"),
                    systemImage: "tag",
                    description: Text(LanguageManager.shared.localized("Add an alias to shorten long tracker domains in torrent cards."))
                )
            } else {
                List {
                    ForEach(aliasManager.rules) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.alias)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(rule.originalDomain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingRule = rule
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel(LanguageManager.shared.localized("Edit"))
                            .tint(.blue)

                            Button(role: .destructive) {
                                aliasManager.remove(originalDomain: rule.originalDomain)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(LanguageManager.shared.localized("Delete"))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(LanguageManager.shared.localized("Tracker Aliases"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LanguageManager.shared.localized("Add Alias"))
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTrackerAliasView(mode: .add)
        }
        .sheet(item: $editingRule) { rule in
            AddTrackerAliasView(mode: .edit(rule))
        }
    }
}

private struct AddTrackerAliasView: View {
    enum Mode {
        case add
        case edit(TrackerAliasRule)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aliasManager = TrackerAliasManager.shared

    let mode: Mode

    @State private var originalDomain = ""
    @State private var alias = ""

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .add:
            _originalDomain = State(initialValue: "")
            _alias = State(initialValue: "")
        case .edit(let rule):
            _originalDomain = State(initialValue: rule.originalDomain)
            _alias = State(initialValue: rule.alias)
        }
    }

    private var canSave: Bool {
        !originalDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var titleKey: String {
        switch mode {
        case .add: return "Add Alias"
        case .edit: return "Edit Alias"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LanguageManager.shared.localized("Original Domain"), text: $originalDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField(LanguageManager.shared.localized("Alias"), text: $alias)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(LanguageManager.shared.localized(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Save")) {
                        let trimmedOriginal = originalDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)

                        if case .edit(let rule) = mode {
                            let oldDomain = aliasManager.normalizeTrackerDomain(rule.originalDomain)
                            let newDomain = aliasManager.normalizeTrackerDomain(trimmedOriginal)
                            if !oldDomain.isEmpty, oldDomain != newDomain {
                                aliasManager.remove(originalDomain: oldDomain)
                            }
                        }

                        aliasManager.upsert(
                            originalDomain: trimmedOriginal,
                            alias: trimmedAlias
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
