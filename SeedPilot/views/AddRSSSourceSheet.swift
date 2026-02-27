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
    @State private var apiKeyString: String = ""
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(LanguageManager.shared.localized("RSS URL"), text: $urlString)
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

                    TextField(LanguageManager.shared.localized("Name"), text: $nameString)
                } header: {
                    Text(LanguageManager.shared.localized("Feed Details"))
                } footer: {
                    Text(LanguageManager.shared.localized("After entering URL, Downix will automatically try to extract the site name."))
                }

                Section {
                    Toggle(LanguageManager.shared.localized("Auto Download"), isOn: $autoDownload)
                    Text(LanguageManager.shared.localized("When enabled, newly published compliant items will be automatically pushed to your downloader."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if isMTeamSourceURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.shared.localized("M-Team API Key"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            SecureField(LanguageManager.shared.localized("Please enter M-Team API Key"), text: $apiKeyString)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Automation"))
                }
                .animation(.easeInOut, value: isMTeamSourceURL)
            }
            .navigationTitle(LanguageManager.shared.localized("Add RSS Source"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localized("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localized("Add")) {
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
            faviconUrl: getFaviconURL(for: urlString),
            apiKey: normalizedApiKey
        )

        modelContext.insert(newSource)
        RSSFeedSourceCloudSyncManager.shared.start(with: modelContext)
        RSSFeedSourceCloudSyncManager.shared.handleLocalSourceConfigsChanged()
        dismiss()
    }

    private func getFaviconURL(for urlString: String) -> String? {
        if urlString.lowercased().contains("m-team.cc") {
            return "https://m-team.cc/favicon.ico"
        }

        // Naive favicon guess: scheme://host/favicon.ico
        guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host() else { return nil }
        return "\(scheme)://\(host)/favicon.ico"
    }

    private var isMTeamSourceURL: Bool {
        urlString.lowercased().contains("m-team.cc")
    }

    private var normalizedApiKey: String? {
        let trimmed = apiKeyString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMTeamSourceURL, !trimmed.isEmpty else { return nil }
        return trimmed
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
