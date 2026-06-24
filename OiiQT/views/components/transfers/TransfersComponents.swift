import SwiftUI

// MARK: - Top Filter Menus
struct TorrentFilterMenuBar: View {
    @Binding var selectedStatuses: Set<TaskStatusFilter>
    @Binding var selectedCategories: Set<String>
    @Binding var selectedTags: Set<String>
    @Binding var selectedTrackers: Set<String>
    @Binding var activeSheet: ActiveFilterSheet?

    let isCategoryFilterSupported: Bool

    private var selectedStatusCount: Int {
        selectedStatuses.filter { $0 != .all }.count
    }

    private var statusTitle: String {
        let base = LanguageManager.shared.localized("Status")
        if selectedStatusCount > 1 {
            return "\(base)(\(selectedStatusCount))"
        }
        guard selectedStatusCount == 1,
              let only = selectedStatuses.first(where: { $0 != .all }) else {
            return base
        }
        return only.title
    }

    private var categoryTitle: String {
        let base = LanguageManager.shared.localized("Category")
        if selectedCategories.count > 1 {
            return "\(base)(\(selectedCategories.count))"
        }
        guard selectedCategories.count == 1, let only = selectedCategories.first else {
            return base
        }
        return only
    }

    private var tagTitle: String {
        let base = LanguageManager.shared.localized("Tags")
        if selectedTags.count > 1 {
            return "\(base)(\(selectedTags.count))"
        }
        guard selectedTags.count == 1, let only = selectedTags.first else {
            return base
        }
        return only
    }

    private var trackerTitle: String {
        let base = LanguageManager.shared.localized("Source")
        if selectedTrackers.count > 1 {
            return "\(base)(\(selectedTrackers.count))"
        }
        guard selectedTrackers.count == 1, let only = selectedTrackers.first else {
            return base
        }
        return only
    }

    var body: some View {
        HStack(spacing: 6) {
            statusButton

            if isCategoryFilterSupported {
                categoryButton
            }

            tagButton
            trackerButton
        }
        .padding(4)
        .frame(height: 40)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusButton: some View {
        buttonContainer {
            activeSheet = .status
        } label: {
            FilterMenuControl(title: statusTitle, isActive: !selectedStatuses.isEmpty)
        }
    }

    @ViewBuilder
    private var categoryButton: some View {
        buttonContainer {
            activeSheet = .category
        } label: {
            FilterMenuControl(title: categoryTitle, isActive: !selectedCategories.isEmpty)
        }
    }

    @ViewBuilder
    private var tagButton: some View {
        buttonContainer {
            activeSheet = .tag
        } label: {
            FilterMenuControl(title: tagTitle, isActive: !selectedTags.isEmpty)
        }
    }

    @ViewBuilder
    private var trackerButton: some View {
        buttonContainer {
            activeSheet = .tracker
        } label: {
            FilterMenuControl(title: trackerTitle, isActive: !selectedTrackers.isEmpty)
        }
    }

    private func buttonContainer(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct FilterMenuControl: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(isActive ? .subheadline.weight(.semibold) : .subheadline.weight(.regular))
        .foregroundColor(isActive ? .primary : .secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule()
                .fill(isActive ? Color(uiColor: .systemBackground) : .clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Sort Menu
struct SortMenuView: View {
    @Binding var sortOption: SortOption
    @Binding var sortAscending: Bool

    var body: some View {
        Menu {
            Section(LanguageManager.shared.localized("Sort")) {
                Picker(LanguageManager.shared.localized("Sort By"), selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.localizedDisplayName).tag(option)
                    }
                }

                Toggle(isOn: $sortAscending) {
                    Label(LanguageManager.shared.localized("Ascending"), systemImage: "arrow.up.arrow.down")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 17, weight: .semibold))
        }
    }
}

// MARK: - Status Bar Component

struct ServerStatusBar: View {
    var appStateManager: AppStateManager

    var body: some View {
        HStack {
            // Left: Assets Snapshot (Seeds + Size)
            HStack(spacing: 12) {
                // Seeding Count
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(appStateManager.displayedSeedingCount)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Total Size
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(appStateManager.displayedSeedingSize))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right: Speeds
            HStack(spacing: 12) {
                SpeedLabel(icon: "arrow.down", speed: appStateManager.displayedDownloadSpeed, color: .green)
                SpeedLabel(icon: "arrow.up", speed: appStateManager.displayedUploadSpeed, color: .blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct SpeedLabel: View {
    let icon: String
    let speed: Int64
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(formatBytes(speed) + "/s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Brand Icon Component
struct ServerBrandIcon: View {
    let type: ServerType?
    let size: CGFloat

    var body: some View {
        Group {
            if let type = type {
                Image(systemName: type == .transmission ? "arrow.down.circle.fill" : "bolt.horizontal.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(type == .transmission ? .orange : .blue)
            } else {
                // All Servers (Grid Icon)
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
