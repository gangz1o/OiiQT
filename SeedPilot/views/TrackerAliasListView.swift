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
    @Environment(AppStateManager.self) private var appStateManager
    @ObservedObject private var aliasManager = TrackerAliasManager.shared

    let mode: Mode

    @State private var originalDomain = ""
    @State private var alias = ""
    @State private var trackerDomainCandidates: [String] = []

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
        !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isDuplicateDomain
    }

    private var titleKey: String {
        switch mode {
        case .add: return "Add Alias"
        case .edit: return "Edit Alias"
        }
    }

    private var editingNormalizedDomain: String? {
        guard case .edit(let rule) = mode else { return nil }
        let normalized = aliasManager.normalizeTrackerDomain(rule.originalDomain)
        return normalized.isEmpty ? nil : normalized
    }

    private var existingNormalizedDomains: Set<String> {
        Set(aliasManager.aliasMap.keys)
    }

    private var normalizedInputDomain: String {
        aliasManager.normalizeTrackerDomain(originalDomain)
    }

    private var isDuplicateDomain: Bool {
        let normalized = normalizedInputDomain
        guard !normalized.isEmpty else { return false }
        if let editingNormalizedDomain, editingNormalizedDomain == normalized {
            return false
        }
        return existingNormalizedDomains.contains(normalized)
    }

    private var selectableTrackerDomains: [String] {
        let excluded = existingNormalizedDomains.subtracting(
            Set([editingNormalizedDomain].compactMap { $0 })
        )
        return trackerDomainCandidates.filter { !excluded.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField(LanguageManager.shared.localized("Original Domain"), text: $originalDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        if !selectableTrackerDomains.isEmpty {
                            Menu {
                                ForEach(selectableTrackerDomains, id: \.self) { domain in
                                    Button(domain) {
                                        originalDomain = domain
                                    }
                                }
                            } label: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LanguageManager.shared.localized("Choose from existing trackers"))
                        }
                    }

                    TextField(LanguageManager.shared.localized("Alias"), text: $alias)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if isDuplicateDomain {
                        Text(LanguageManager.shared.localized("This tracker domain already exists"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localized(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                rebuildTrackerDomainCandidates()
            }
            .onChange(of: appStateManager.tasksRevision) { _, _ in
                rebuildTrackerDomainCandidates()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Save")) {
                        guard !isDuplicateDomain else { return }
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

    private func rebuildTrackerDomainCandidates() {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(appStateManager.allTasks.count, 256))

        for task in appStateManager.allTasks {
            let host = task.trackerHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, host != "--" else { continue }
            let normalized = aliasManager.normalizeTrackerDomain(host)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }

        trackerDomainCandidates = result.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
