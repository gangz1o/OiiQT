//
//  EditRSSRuleView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI

struct EditRSSRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appStateManager // To access servers

    @Binding var source: RSSFeedSource

    @State private var newIncludeKeyword: String = ""
    @State private var newExcludeKeyword: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Keywords
                Section("关键词过滤") {
                    VStack(alignment: .leading) {
                        Text("包含关键词 (必须满足)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Token List
                        FlowLayout(spacing: 8) {
                            ForEach(source.includeKeywords, id: \.self) { keyword in
                                KeywordToken(text: keyword, color: .green) {
                                    if let idx = source.includeKeywords.firstIndex(of: keyword) {
                                        source.includeKeywords.remove(at: idx)
                                    }
                                }
                            }
                            // Input
                            TextField("添加...", text: $newIncludeKeyword)
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

                    VStack(alignment: .leading) {
                        Text("排除关键词 (不能包含)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Token List
                        FlowLayout(spacing: 8) {
                            ForEach(source.excludeKeywords, id: \.self) { keyword in
                                KeywordToken(text: keyword, color: .red) {
                                    if let idx = source.excludeKeywords.firstIndex(of: keyword) {
                                        source.excludeKeywords.remove(at: idx)
                                    }
                                }
                            }
                            // Input
                            TextField("添加...", text: $newExcludeKeyword)
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
                }

                // Section 2: Size Limits
                Section("体积限制 (GB)") {
                    HStack {
                        Text("最小")
                        Spacer()
                        TextField("无限制", value: Binding(
                            get: { source.minSizeGB ?? 0 },
                            set: { source.minSizeGB = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }

                    HStack {
                        Text("最大")
                        Spacer()
                        TextField("无限制", value: Binding(
                            get: { source.maxSizeGB ?? 0 },
                            set: { source.maxSizeGB = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }
                }

                // Section 3: Routing
                Section(header: Text("路由选择"), footer: Text("指定下载任务推送到的服务器。例如将动漫推送到 qBittorrent。")) {
                    Picker("目标服务器", selection: $source.targetServerId) {
                        Text("默认 (自动选择)").tag(UUID?.none)

                        ForEach(appStateManager.servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }

                // Section 4: Testing
                Section {
                    Button("测试规则匹配") {
                        // TODO: Implement a test sheet
                    }
                }
            }
            .navigationTitle("编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
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
