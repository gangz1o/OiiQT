//
//  AddRSSSourceSheet.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/16.
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct AddRSSSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Removed Binding sources

    @State private var urlString: String = ""
    @State private var nameString: String = ""
    @State private var autoDownload: Bool = false
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("RSS URL", text: $urlString)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .onChange(of: urlString) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                // Only update if significantly different to avoid loop, or just parse
                                parseDomainAndAutoFill(url: trimmed)
                            }

                        // Paste Button
                        Button {
                            if let string = UIPasteboard.general.string {
                                urlString = string.trimmingCharacters(in: .whitespacesAndNewlines)
                                parseDomainAndAutoFill(url: urlString)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.borderless)
                    }

                    TextField("名称", text: $nameString)
                } header: {
                    Text("订阅详情")
                } footer: {
                    Text("输入 URL 后，SeedPilot 将自动尝试提取站点名称。")
                }

                Section {
                    Toggle("自动下载", isOn: $autoDownload)
                } header: {
                    Text("自动化")
                } footer: {
                    Text("开启后，新发布的合规条目将自动推送到下载器。")
                }
            }
            .navigationTitle("添加 RSS 源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addSource()
                    }
                    .disabled(urlString.isValidURL == false || nameString.isEmpty)
                }
            }
            .onAppear {
                checkClipboard()
            }
        }
    }

    private func checkClipboard() {
        if let string = UIPasteboard.general.string {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isValidURL {
                urlString = trimmed
                // Trigger shared parsing logic
                parseDomainAndAutoFill(url: trimmed)
            }
        }
    }

    private func parseDomainAndAutoFill(url: String) {
        // Simple domain parsing logic
        guard let urlObj = URL(string: url), let host = urlObj.host() else { return }

        // Remove 'www.'
        let cleanHost = host.replacingOccurrences(of: "www.", with: "")

        // If name is empty or looks like a previous auto-fill, update it
        if nameString.isEmpty || nameString.lowercased().contains(cleanHost.split(separator: ".").first ?? "") {
            // Capitalize first letter of domain
            let components = cleanHost.split(separator: ".")
            if let first = components.first {
                nameString = String(first).capitalized
            }
        }
    }

    private func addSource() {
        let newSource = RSSFeedSource(
            name: nameString,
            url: urlString,
            isEnabled: true,
            lastUpdated: Date(), // Now
            autoDownload: autoDownload,
            unreadCount: 0,
            faviconUrl: getFaviconURL(for: urlString)
        )

        modelContext.insert(newSource)
        dismiss()
    }

    private func getFaviconURL(for urlString: String) -> String? {
        // Naive favicon guess: scheme://host/favicon.ico
        guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host() else { return nil }
        return "\(scheme)://\(host)/favicon.ico"
    }
}

// Helper extension logic (internal)
fileprivate extension String {
    var isValidURL: Bool {
        // Simple check
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("http") && URL(string: trimmed) != nil
    }
}

#Preview {
    AddRSSSourceSheet()
}
