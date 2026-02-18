//
//  EditRSSRuleView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import SwiftData

struct EditRSSRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appStateManager // To access servers

    @Bindable var source: RSSFeedSource

    @State private var newIncludeKeyword: String = ""
    @State private var newExcludeKeyword: String = ""

    @State private var showingMatchPreview = false

    var body: some View {
        NavigationStack {
            Form {
                // Section 0: Source Info (One-Stop Management)
                Section(LanguageManager.shared.localized("Source Information")) {
                    HStack {
                        Text(LanguageManager.shared.localized("Name"))
                        Divider()
                        TextField(LanguageManager.shared.localized("Give it a name"), text: $source.name)
                    }

                    HStack {
                        Text(LanguageManager.shared.localized("URL"))
                        Divider()
                        TextField(LanguageManager.shared.localized("http://..."), text: $source.url)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Section 1: Routing (Moved to Top)
                Section(header: Text(LanguageManager.shared.localized("Routing")), footer: Text(LanguageManager.shared.localized("Specify the server where matching download tasks should be pushed."))) {
                    Picker(LanguageManager.shared.localized("Target Server"), selection: $source.targetServerId) {
                        Text(LanguageManager.shared.localized("Default (Auto Select)")).tag(UUID?.none)

                        ForEach(appStateManager.servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }

                // Section 2: Storage Settings
                Section(LanguageManager.shared.localized("Storage Settings")) {
                    HStack {
                        Text(LanguageManager.shared.localized("Save Path"))
                        Spacer()
                        TextField(LanguageManager.shared.localized("/downloads/..."), text: $source.savePath)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !source.savePath.isEmpty {
                            Button(action: { source.savePath = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack {
                        Text(LanguageManager.shared.localized("Category"))
                        Spacer()
                        TextField(LanguageManager.shared.localized("Category"), text: $source.category)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Section 3: Filters (Keywords + Episode)
                Section(LanguageManager.shared.localized("Smart Filters")) {
                    // Include
                    VStack(alignment: .leading) {
                        Text(LanguageManager.shared.localized("Include Keywords (Must Include)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(source.includeKeywords, id: \.self) { keyword in
                                KeywordToken(text: keyword, color: .green) {
                                    if let idx = source.includeKeywords.firstIndex(of: keyword) {
                                        source.includeKeywords.remove(at: idx)
                                    }
                                }
                            }
                            TextField(LanguageManager.shared.localized("Add..."), text: $newIncludeKeyword)
                                .font(.subheadline)
                                .frame(width: 80)
                                .onSubmit {
                                    if !newIncludeKeyword.isEmpty {
                                        source.includeKeywords.append(newIncludeKeyword)
                                        newIncludeKeyword = ""
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)

                    // Exclude
                    VStack(alignment: .leading) {
                        Text(LanguageManager.shared.localized("Exclude Keywords (Must Exclude)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(source.excludeKeywords, id: \.self) { keyword in
                                KeywordToken(text: keyword, color: .red) {
                                    if let idx = source.excludeKeywords.firstIndex(of: keyword) {
                                        source.excludeKeywords.remove(at: idx)
                                    }
                                }
                            }
                            TextField(LanguageManager.shared.localized("Add..."), text: $newExcludeKeyword)
                                .font(.subheadline)
                                .frame(width: 80)
                                .onSubmit {
                                    if !newExcludeKeyword.isEmpty {
                                        source.excludeKeywords.append(newExcludeKeyword)
                                        newExcludeKeyword = ""
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)

                    // Episode Filter
                    VStack(alignment: .leading) {
                        Text(LanguageManager.shared.localized("Episode Range (Episode Filter)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(LanguageManager.shared.localized("e.g. 01-12 or S01E01-E10"), text: $source.episodeFilter)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .onChange(of: source.episodeFilter) { _, newValue in
                                // Simple validation: allow digits, letters, -, ;, space
                                let filtered = newValue.filter { "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-; ".contains($0) }
                                if filtered != newValue {
                                    source.episodeFilter = filtered
                                }
                            }
                    }
                    .padding(.vertical, 4)
                }

                // Section 4: Size Limits
                Section(LanguageManager.shared.localized("Size Limits (GB)")) {
                    HStack {
                        Text(LanguageManager.shared.localized("Min"))
                        Spacer()
                        TextField(LanguageManager.shared.localized("Unlimited"), value: Binding(
                            get: { source.minSizeGB ?? 0 },
                            set: { source.minSizeGB = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }

                    HStack {
                        Text(LanguageManager.shared.localized("Max"))
                        Spacer()
                        TextField(LanguageManager.shared.localized("Unlimited"), value: Binding(
                            get: { source.maxSizeGB ?? 0 },
                            set: { source.maxSizeGB = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }
                }

                // Section 5: Execution Strategy
                Section(LanguageManager.shared.localized("Task Strategy")) {
                    Toggle(LanguageManager.shared.localized("Add in Paused State"), isOn: $source.addPaused)

                    Picker(LanguageManager.shared.localized("Priority"), selection: $source.priority) {
                        Text(LanguageManager.shared.localized("Low")).tag(-1)
                        Text(LanguageManager.shared.localized("Default")).tag(0)
                        Text(LanguageManager.shared.localized("High")).tag(1)
                    }
                }

                // Section 6: Testing
                Section(footer: Text(LanguageManager.shared.localized("After saving, newly published compliant items will be automatically pushed to the server."))) {
                    Button(LanguageManager.shared.localized("Test Rule Matching")) {
                        showingMatchPreview = true
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localized("Edit Rules"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMatchPreview) {
                RuleMatchPreviewView(source: source)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// Simple Token View
struct KeywordToken: View {
    let text: String
    let color: Color
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// Simple FlowLayout Helper
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        return rows.last?.maxY ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        for row in rows {
            for element in row.elements {
                element.subview.place(at: CGPoint(x: bounds.minX + element.rect.minX, y: bounds.minY + element.rect.minY), proposal: .unspecified)
            }
        }
    }

    struct Row {
        var elements: [Element] = []
        var maxY: CGSize = .zero
    }

    struct Element {
        var subview: LayoutSubview
        var rect: CGRect
    }

    func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        var x: CGFloat = 0
        var y: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && !currentRow.elements.isEmpty {
                // New Line
                y += currentRow.maxY.height + spacing
                x = 0
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.elements.append(Element(subview: subview, rect: CGRect(origin: CGPoint(x: x, y: y), size: size)))
            currentRow.maxY.height = max(currentRow.maxY.height, size.height)
            x += size.width + spacing
        }

        if !currentRow.elements.isEmpty {
            currentRow.maxY.height += y
             rows.append(currentRow)
        }

        return rows
    }
}
