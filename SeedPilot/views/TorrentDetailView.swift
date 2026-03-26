//
//  TorrentDetailView.swift
//  SeedPilot
//
//  Created by SeedPilot AI on 2026/2/17.
//

import SwiftUI
import SwiftData

struct TorrentDetailView: View {
    let task: TorrentTask
    var appStateManager: AppStateManager

    @AppStorage("showTMDBData") private var tmdbPosterEnabled: Bool = false
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var tmdbItem: TMDBItem?
    @State private var isLoadingTMDB = false

    // Derived properties
    private var serverName: String {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.name ?? LanguageManager.shared.localized("Unknown Server")
    }

    private var serverType: ServerType? {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.type
    }

    /// All tasks that are cross-seed instances of this torrent.
    /// Strictly matches by hash only — zero false positives.
    /// Excludes self via the globally unique composite id.
    private var crossSeedTorrents: [TorrentTask] {
        guard !task.hash.isEmpty else { return [] }
        return appStateManager.allTasks.filter { torrent in
            torrent.hash.lowercased() == task.hash.lowercased()
                && torrent.id != task.id
        }
    }

    private var displayCategory: String? {
        guard let serverType, serverType != .transmission else { return nil }
        let trimmed = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedTags: [String] {
        Array(
            Set(
                task.tags
                    .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasTaxonomyMetadata: Bool {
        displayCategory != nil || !normalizedTags.isEmpty
    }

    private static let taskTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private var taskErrorDetail: String? {
        let normalizedMessage = task.errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptyMessage = (normalizedMessage?.isEmpty == false) ? normalizedMessage : nil

        switch serverType {
        case .transmission:
            if let nonEmptyMessage { return nonEmptyMessage }

            switch task.errorCode ?? 0 {
            case 1:
                return LanguageManager.shared.localized("Transmission tracker warning")
            case 2:
                return LanguageManager.shared.localized("Transmission tracker error")
            case 3:
                return LanguageManager.shared.localized("Transmission local error")
            case let code where code != 0:
                return String(
                    format: LanguageManager.shared.localized("Transmission reported error code: %d"),
                    code
                )
            default:
                return task.status == .error
                    ? LanguageManager.shared.localized("Transmission reported an error")
                    : nil
            }

        case .qBittorrent:
            guard task.status == .error else { return nil }
            let stateToken = nonEmptyMessage?.lowercased() ?? ""

            switch stateToken {
            case "missingfiles":
                return LanguageManager.shared.localized("Torrent data files are missing. Verify storage mount points or use Set Location.")
            case "unregistered", "unregisteredtorrent":
                return LanguageManager.shared.localized("Torrent is unregistered on tracker.")
            case "error":
                return LanguageManager.shared.localized("qBittorrent reported a torrent error")
            case "unknown":
                return LanguageManager.shared.localized("qBittorrent reported an unknown torrent state")
            case "":
                return LanguageManager.shared.localized("qBittorrent reported a torrent error")
            default:
                return String(
                    format: LanguageManager.shared.localized("qBittorrent reported state: %@"),
                    stateToken
                )
            }

        case nil:
            return nonEmptyMessage
        }
    }

    var body: some View {
        List {
            // MARK: - 1. Header Section
            Section {
                if tmdbPosterEnabled, let item = tmdbItem {
                    // Pro Mode with Match
                    HStack(alignment: .top, spacing: 16) {
                        // Poster (2:3 aspect ratio)
                        if let url = item.fullPosterURL {
                            SimpleCachedImage(
                                url: url,
                                downsampleSize: CGSize(width: 100, height: 150)
                            )
                                .aspectRatio(2/3, contentMode: .fit)
                                .frame(width: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 100, height: 150)
                                .cornerRadius(8)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.title3.bold())
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                if let rating = item.voteAverage, rating > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption.monospacedDigit().bold())
                                    }
                                }

                                Text(item.year)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }

                            if let overview = item.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            } else {
                                Text(LanguageManager.shared.localized("No Overview"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // Standard Mode / No Match
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(.headline)
                            .lineLimit(3)

                        Text(task.status.localizedDisplayName)
                             .font(.subheadline)
                             .foregroundStyle(task.status.color)
                             .lineLimit(1)
                             .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            // MARK: - 2. Static Data Report (The Static Report)
            Section {
                if hasTaxonomyMetadata {
                    HStack(alignment: .top) {
                        Text("\(LanguageManager.shared.localized("Category")) / \(LanguageManager.shared.localized("Tags"))")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 12)

                        FlowLayout(spacing: 8, rowAlignment: .trailing) {
                            if let category = displayCategory {
                                ColoredTagPill(
                                    text: category,
                                    font: .caption.weight(.semibold),
                                    horizontalPadding: 10,
                                    verticalPadding: 5,
                                    color: TagColorManager.color(for: "category:\(category)")
                                )
                                .fixedSize(horizontal: true, vertical: false)
                            }

                            ForEach(normalizedTags, id: \.self) { tag in
                                ColoredTagPill(
                                    text: tag,
                                    font: .caption.weight(.semibold),
                                    horizontalPadding: 10,
                                    verticalPadding: 5
                                )
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                // 速率 Rate
                HStack {
                    Text(LanguageManager.shared.localized("Rate"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 16) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                            Text(formatBytes(task.downloadSpeed) + "/s")
                        }
                        .foregroundStyle(.blue)

                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                            Text(formatBytes(task.uploadSpeed) + "/s")
                        }
                        .foregroundStyle(.green)
                    }
                    .font(.callout.monospacedDigit())
                }

                // 流量 Traffic
                HStack {
                    Text(LanguageManager.shared.localized("Traffic"))
                         .foregroundStyle(.secondary)
                    Spacer()
                    Text("↓\(task.downloadedString)  ↑\(task.uploadedString)")
                        .font(.callout.monospacedDigit())
                }

                // 管理 Management (Ratio)
                HStack {
                    Text(LanguageManager.shared.localized("Ratio"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", task.ratio))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(ratioColor(task.ratio))
                }

                HStack {
                    Text(LanguageManager.shared.localized("Date Added"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedTaskTimestamp(task.addedTime))
                        .font(.callout.monospacedDigit())
                }

                HStack {
                    Text(LanguageManager.shared.localized("Completion Time"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedTaskTimestamp(task.completionDate))
                        .font(.callout.monospacedDigit())
                }

                // 存储 Storage (Save Path)
                HStack {
                    Text(LanguageManager.shared.localized("Save Path"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.savePath)
                        .font(.callout.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled) // Allow copying
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = task.savePath
                            } label: {
                                Label(LanguageManager.shared.localized("Copy Path"), systemImage: "doc.on.doc")
                            }
                        }
                }

                // 属性 Attributes
                HStack {
                    Text(LanguageManager.shared.localized("File Size"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.sizeString)
                         .font(.callout.monospacedDigit())
                }

                if let taskErrorDetail {
                    HStack(alignment: .top) {
                        Text(LanguageManager.shared.localized("Error Details"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(taskErrorDetail)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                    }
                }

                NavigationLink {
                    TorrentPeerDetailListView(task: task, appStateManager: appStateManager)
                } label: {
                    HStack {
                        Text(LanguageManager.shared.localized("Peers"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(task.displayText.peers)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }

                NavigationLink {
                    TorrentTrackerDetailListView(task: task, appStateManager: appStateManager)
                } label: {
                    HStack {
                        Text(LanguageManager.shared.localized("Tracker"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(task.trackerHost)
                            .font(.callout.monospacedDigit())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.primary)
                    }
                }

                // MARK: Cross-Seed Entry
                if crossSeedTorrents.isEmpty {
                    HStack {
                        Text(LanguageManager.shared.localized("Cross-Seed"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(LanguageManager.shared.localized("No Related Tasks"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    NavigationLink {
                        CrossSeedDetailView(
                            torrents: crossSeedTorrents,
                            servers: appStateManager.servers
                        )
                    } label: {
                        HStack {
                            Text(LanguageManager.shared.localized("Cross-Seed"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(
                                String(
                                    format: LanguageManager.shared.localized("Cross-Seed Server Count Format"),
                                    crossSeedTorrents.count
                                )
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text(LanguageManager.shared.localized("Server"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(serverName)
                        .font(.callout)
                }
            } header: {
                Text(LanguageManager.shared.localized("Data Brief"))
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(LanguageManager.shared.localized("Task Details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(task.id)-\(languageManager.selectedLanguage.rawValue)") {
            await loadTMDBData()
        }
    }

    private func loadTMDBData() async {
        guard tmdbPosterEnabled else { return }
        isLoadingTMDB = true
        if let details = await TMDBService.shared.fetchDetails(hash: task.hash, name: task.name, context: modelContext) {
            self.tmdbItem = details
        }
        isLoadingTMDB = false
    }

    private func ratioColor(_ ratio: Double) -> Color {
        if ratio >= 1.0 { return .green }
        if ratio >= 0.5 { return .orange }
        return .red
    }

    private func formattedTaskTimestamp(_ date: Date?) -> String {
        guard let date, date.timeIntervalSince1970 > 0 else { return "--" }
        return Self.taskTimestampFormatter.string(from: date)
    }
}

private struct TorrentPeerDetailListView: View {
    let task: TorrentTask
    var appStateManager: AppStateManager

    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var peers: [TorrentPeerInfo] = []
    @State private var peerRows: [TorrentPeerRowModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var showingActionError = false
    @State private var showingAddPeersSheet = false
    @State private var addPeersDraft = ""
    @State private var isSubmittingAddPeers = false

    private var supportsPeerManagement: Bool {
        appStateManager.servers.first(where: { $0.id == task.serverID })?.type == .qBittorrent
    }

    var body: some View {
        List {
            if isLoading && peerRows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let errorMessage, peerRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        languageManager.localized("Failed to load peer details"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
                .listRowBackground(Color.clear)
            } else if peerRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        languageManager.localized("No Peer Data"),
                        systemImage: "person.2.slash",
                        description: Text(languageManager.localized("No peer status available"))
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(peerRows) { row in
                        peerRowCell(row)
                    }
                } header: {
                    Text(languageManager.localized("Peers"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(languageManager.localized("Peers"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadPeers(showLoadingIndicator: false)
        }
        .task(id: task.id) {
            await loadPeers(showLoadingIndicator: true)
        }
        .onChange(of: languageManager.selectedLanguage.rawValue) { _, _ in
            rebuildPeerRowsFromCurrentPeers()
        }
        .sheet(isPresented: $showingAddPeersSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text(languageManager.localized("Peers to Add (one per line)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $addPeersDraft)
                            .frame(minHeight: 180)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text(languageManager.localized("Format: IPv4:port / [IPv6]:port"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(languageManager.localized("Add peers users..."))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(languageManager.localized("Cancel")) {
                            showingAddPeersSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(languageManager.localized("Confirm")) {
                            submitAddPeersFromDraft()
                        }
                        .disabled(parsedPeerInputs(from: addPeersDraft).isEmpty || isSubmittingAddPeers)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(languageManager.localized("Error"), isPresented: $showingActionError) {
            Button(languageManager.localized("OK"), role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
    }

    private func loadPeers(showLoadingIndicator: Bool) async {
        if showLoadingIndicator || peerRows.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let fetched = try await appStateManager.fetchPeers(for: task)
            errorMessage = nil
            let mappedRows = fetched.map(buildPeerRowModel)

            if fetched != peers || mappedRows != peerRows {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    peers = fetched
                    peerRows = mappedRows
                }
            }
        } catch {
            if peerRows.isEmpty {
                errorMessage = localizedErrorMessage(error)
            }
        }
    }

    private func banPeer(_ peer: TorrentPeerInfo) {
        Task {
            do {
                try await appStateManager.banPeers(for: task, peers: [peer.endpoint])
                await loadPeers(showLoadingIndicator: false)
            } catch {
                await MainActor.run {
                    actionErrorMessage = localizedErrorMessage(error)
                    showingActionError = true
                }
            }
        }
    }

    private func peerRowCell(_ row: TorrentPeerRowModel) -> some View {
        TorrentPeerCardView(
            row: row,
            supportsPeerManagement: supportsPeerManagement,
            copyTitle: languageManager.localized("Copy IP:Port"),
            addPeersTitle: languageManager.localized("Add peers users..."),
            banTitle: languageManager.localized("Permanently Ban User"),
            onCopy: {
                UIPasteboard.general.string = row.peer.endpoint
            },
            onAddPeer: {
                presentAddPeersSheet()
            },
            onBanPeer: {
                banPeer(row.peer)
            }
        )
        .equatable()
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func rebuildPeerRowsFromCurrentPeers() {
        let rebuilt = peers.map(buildPeerRowModel)
        guard rebuilt != peerRows else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            peerRows = rebuilt
        }
    }

    private func buildPeerRowModel(_ peer: TorrentPeerInfo) -> TorrentPeerRowModel {
        let location = locationDisplay(for: peer)
        return TorrentPeerRowModel(
            peer: peer,
            locationFlag: location.flag,
            locationLabel: location.label,
            normalizedProgress: normalizedProgress(peer.progress),
            progressText: progressText(peer.progress),
            clientText: peer.client ?? "--",
            connectionText: connectionValue(for: peer),
            downloadSpeedText: speedText(peer.downloadSpeed),
            uploadSpeedText: speedText(peer.uploadSpeed),
            downloadedText: bytesText(peer.downloaded),
            uploadedText: bytesText(peer.uploaded)
        )
    }

    private func presentAddPeersSheet() {
        isSubmittingAddPeers = false
        addPeersDraft = ""
        showingAddPeersSheet = true
    }

    private func submitAddPeersFromDraft() {
        guard !isSubmittingAddPeers else { return }
        let peersToAdd = parsedPeerInputs(from: addPeersDraft)
        guard !peersToAdd.isEmpty else { return }

        isSubmittingAddPeers = true
        Task {
            do {
                try await appStateManager.addPeers(for: task, peers: peersToAdd)
                await MainActor.run {
                    isSubmittingAddPeers = false
                    addPeersDraft = ""
                    showingAddPeersSheet = false
                }
                await loadPeers(showLoadingIndicator: false)
            } catch {
                await MainActor.run {
                    isSubmittingAddPeers = false
                    actionErrorMessage = localizedErrorMessage(error)
                    showingActionError = true
                }
            }
        }
    }

    private func parsedPeerInputs(from raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let candidates = normalized.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" || $0 == "|" })

        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(candidates.count)

        for candidate in candidates {
            let trimmed = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }

        return result
    }

    private func countryText(for peer: TorrentPeerInfo) -> String? {
        let country = peer.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !country.isEmpty { return country }
        let code = peer.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return code.isEmpty ? nil : code
    }

    private func locationDisplay(for peer: TorrentPeerInfo) -> (flag: String, label: String) {
        let countryCode = peer.countryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let rawCountry = countryText(for: peer) ?? "--"
        let normalizedCountryLower = rawCountry.lowercased()
        let isTaiwan = countryCode == "TW" ||
            rawCountry.contains("台湾") ||
            normalizedCountryLower.contains("taiwan")

        if isTaiwan {
            return ("🇨🇳", languageManager.localized("Taiwan Province, China"))
        }

        return (flagEmoji(from: countryCode) ?? "🌐", rawCountry)
    }

    private func flagEmoji(from countryCode: String?) -> String? {
        guard let countryCode,
              countryCode.count == 2 else {
            return nil
        }

        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(2)

        for scalar in countryCode.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90,
                  let regional = UnicodeScalar(127397 + scalar.value) else {
                return nil
            }
            scalars.append(regional)
        }

        return String(String.UnicodeScalarView(scalars))
    }

    private func connectionValue(for peer: TorrentPeerInfo) -> String {
        let connection = peer.connection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let flags = peer.flags?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (connection.isEmpty, flags.isEmpty) {
        case (false, false):
            return "\(connection) · \(flags)"
        case (false, true):
            return connection
        case (true, false):
            return flags
        case (true, true):
            return "--"
        }
    }

    private func normalizedProgress(_ value: Double?) -> Double {
        guard let value else { return 0 }
        let normalized = value > 1 ? value / 100.0 : value
        return min(max(normalized, 0), 1)
    }

    private func speedText(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return "\(formatBytes(max(0, value)))/s"
    }

    private func bytesText(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return formatBytes(max(0, value))
    }

    private func progressText(_ value: Double?) -> String {
        guard let value else { return "--" }
        let clamped = normalizedProgress(value)
        return String(format: "%.1f%%", clamped * 100)
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if case let TorrentClientError.apiError(message) = error {
            return languageManager.localized(message)
        }
        return error.localizedDescription
    }
}

private struct TorrentPeerRowModel: Identifiable, Equatable {
    let peer: TorrentPeerInfo
    let locationFlag: String
    let locationLabel: String
    let normalizedProgress: Double
    let progressText: String
    let clientText: String
    let connectionText: String
    let downloadSpeedText: String
    let uploadSpeedText: String
    let downloadedText: String
    let uploadedText: String

    var id: String { peer.id }
}

private struct TorrentPeerCardView: View, Equatable {
    static func == (lhs: TorrentPeerCardView, rhs: TorrentPeerCardView) -> Bool {
        lhs.row == rhs.row &&
        lhs.supportsPeerManagement == rhs.supportsPeerManagement &&
        lhs.copyTitle == rhs.copyTitle &&
        lhs.addPeersTitle == rhs.addPeersTitle &&
        lhs.banTitle == rhs.banTitle
    }

    let row: TorrentPeerRowModel
    let supportsPeerManagement: Bool
    let copyTitle: String
    let addPeersTitle: String
    let banTitle: String
    let onCopy: () -> Void
    let onAddPeer: () -> Void
    let onBanPeer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(row.locationFlag) \(row.locationLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(row.peer.endpoint)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.8)
                    .textSelection(.enabled)

                Spacer(minLength: 8)
            }

            HStack(alignment: .center, spacing: 8) {
                ProgressView(value: row.normalizedProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 4)

                Text(row.progressText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(row.clientText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(row.connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(spacing: 10) {
                        metricText(
                            symbol: "arrow.down",
                            value: row.downloadSpeedText,
                            color: .blue,
                            font: .subheadline.monospacedDigit().weight(.medium)
                        )
                        metricText(
                            symbol: "arrow.up",
                            value: row.uploadSpeedText,
                            color: .green,
                            font: .subheadline.monospacedDigit().weight(.medium)
                        )
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 10) {
                        metricText(
                            symbol: "arrow.down",
                            value: row.downloadedText,
                            color: Color.blue.opacity(0.75),
                            font: .footnote.monospacedDigit().weight(.medium)
                        )
                        metricText(
                            symbol: "arrow.up",
                            value: row.uploadedText,
                            color: Color.green.opacity(0.75),
                            font: .footnote.monospacedDigit().weight(.medium)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .shadow(color: Color.black.opacity(0.04), radius: 1.5, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(action: onCopy) {
                Label(copyTitle, systemImage: "doc.on.doc")
            }

            Button(action: onAddPeer) {
                Label(addPeersTitle, systemImage: "person.badge.plus")
            }
            .disabled(!supportsPeerManagement)

            Divider()

            Button(role: .destructive, action: onBanPeer) {
                Label(banTitle, systemImage: "nosign")
            }
            .disabled(!supportsPeerManagement)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if supportsPeerManagement {
                Button(role: .destructive, action: onBanPeer) {
                    Label(banTitle, systemImage: "nosign")
                }
            }
        }
    }

    @ViewBuilder
    private func metricText(symbol: String, value: String, color: Color, font: Font) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(value)
        }
        .font(font)
        .foregroundStyle(color)
    }
}

private struct TorrentTrackerDetailListView: View {
    let task: TorrentTask
    var appStateManager: AppStateManager

    @State private var trackers: [TorrentTrackerInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && trackers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else if let errorMessage, trackers.isEmpty {
                Section {
                    ContentUnavailableView(
                        LanguageManager.shared.localized("Failed to load tracker details"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
                .listRowBackground(Color.clear)
            } else if trackers.isEmpty {
                Section {
                    ContentUnavailableView(
                        LanguageManager.shared.localized("No Tracker Data"),
                        systemImage: "link",
                        description: Text(LanguageManager.shared.localized("No tracker status available"))
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(trackers) { tracker in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                if let tier = tracker.tier {
                                    Text("L\(tier)")
                                        .font(.caption2.monospacedDigit().bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                                }

                                Text(tracker.url)
                                    .font(.callout.monospacedDigit())
                                    .lineLimit(2)
                                    .truncationMode(.middle)

                                Spacer(minLength: 8)

                                Text(tracker.status.localizedText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(tracker.status.color)
                                    .fixedSize()
                            }

                            HStack(spacing: 14) {
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Peers"),
                                    value: tracker.peers
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Seeds"),
                                    value: tracker.seeds
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Leeches"),
                                    value: tracker.leeches
                                )
                                TrackerMetricPair(
                                    title: LanguageManager.shared.localized("Downloads"),
                                    value: tracker.downloaded
                                )
                            }

                            if let message = tracker.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(tracker.status == .failed ? .red : .secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(LanguageManager.shared.localized("Tracker"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LanguageManager.shared.localized("Tracker"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadTrackers(showLoadingIndicator: false)
        }
        .task(id: task.id) {
            await loadTrackers(showLoadingIndicator: true)
        }
    }

    private func loadTrackers(showLoadingIndicator: Bool) async {
        if showLoadingIndicator || trackers.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let fetched = try await appStateManager.fetchTrackers(for: task)
            errorMessage = nil
            if fetched != trackers {
                trackers = fetched
            }
        } catch {
            if trackers.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct TrackerMetricPair: View {
    let title: String
    let value: Int?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "--")
                .foregroundStyle(.primary)
        }
        .font(.caption.monospacedDigit())
    }
}
