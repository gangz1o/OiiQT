import SwiftUI

struct CategorySelectionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    let categories: [String]
    let onConfirm: (String) -> Void

    @State private var selectedCategory: String

    init(categories: [String], initialSelection: String = "", onConfirm: @escaping (String) -> Void) {
        self.categories = categories
        self.onConfirm = onConfirm
        _selectedCategory = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    categoryRow(title: languageManager.localized("Default"), value: "")
                    ForEach(categories, id: \.self) { category in
                        categoryRow(title: category, value: category)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(languageManager.localized("Set Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Confirm")) {
                        onConfirm(selectedCategory)
                        dismiss()
                    }
                }
            }
        }
    }

    private func categoryRow(title: String, value: String) -> some View {
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                selectedCategory = value
            }
        } label: {
            HStack(spacing: 12) {
                SelectionCircleIndicator(isSelected: selectedCategory == value)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TagMultiSelectSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languageManager = LanguageManager.shared

    let availableTags: [String]
    let onConfirm: ([String]) -> Void

    @State private var selectedTags: Set<String>
    @State private var draftTag = ""

    init(availableTags: [String], initialSelection: Set<String>, onConfirm: @escaping ([String]) -> Void) {
        self.availableTags = availableTags
        self.onConfirm = onConfirm
        _selectedTags = State(initialValue: initialSelection)
    }

    private var displayTags: [String] {
        Array(Set(availableTags).union(selectedTags))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        TextField(languageManager.localized("Tag Name"), text: $draftTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(languageManager.localized("Add")) {
                            let trimmed = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            selectedTags.insert(trimmed)
                            draftTag = ""
                        }
                    }
                }

                Section {
                    if displayTags.isEmpty {
                        Text(languageManager.localized("No Tags"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayTags, id: \.self) { tag in
                            Button {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    SelectionCircleIndicator(isSelected: selectedTags.contains(tag))
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(languageManager.localized("Edit Tags"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.localized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.localized("Confirm")) {
                        onConfirm(
                            selectedTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SelectionCircleIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)

            Circle()
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.45),
                    lineWidth: 1.7
                )

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.65)
        }
        .frame(width: 24, height: 24)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
    }
}
