import SwiftUI

struct TransfersEmptyStatesView: View {
    @Bindable var viewModel: TransfersViewModel
    var appStateManager: AppStateManager
    
    var body: some View {
        if shouldShowServerEmptyState {
            serverEmptyStateView
        } else if shouldShowTasksLoadingState {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text(LanguageManager.shared.localized("Loading..."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        } else if viewModel.isFilteringTasks && viewModel.filteredTasks.isEmpty {
            filteringTransitionStateView
        } else if viewModel.filteredTasks.isEmpty {
            if !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ContentUnavailableView(
                    LanguageManager.shared.localized("No Tasks"),
                    systemImage: "tray",
                    description: Text(LanguageManager.shared.localized("No tasks match the current filters"))
                )
            }
        }
    }
    
    private var isTransfersTabActive: Bool {
        appStateManager.selectedTab == .transfers
    }
    
    var shouldShowServerEmptyState: Bool {
        if appStateManager.servers.isEmpty { return true }
        if let id = appStateManager.activeServerId,
           let server = appStateManager.servers.first(where: { $0.id == id }),
           server.isOnline == false,
           appStateManager.hasInitialDataLoaded {
            return true
        }
        return false
    }
    
    var shouldShowTasksLoadingState: Bool {
        guard isTransfersTabActive else { return false }
        guard viewModel.filteredTasks.isEmpty else { return false }
        guard !appStateManager.servers.isEmpty else { return false }

        // Keep full-screen loading for first load only; avoid empty-state flicker during periodic refresh/filter passes.
        guard !appStateManager.hasInitialDataLoaded else { return false }
        return appStateManager.isRefreshingTasks || viewModel.isFilteringTasks || appStateManager.allTasks.isEmpty
    }
    
    private var filteringTransitionStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(LanguageManager.shared.localized("Filtering tasks..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var serverEmptyStateView: some View {
        ContentUnavailableView {
            Label(
                LanguageManager.shared.localized("No Available Server"),
                systemImage: "server.rack"
            )
        } description: {
            Text(LanguageManager.shared.localized("Please check your server configuration or network status."))
        } actions: {
            Button {
                appStateManager.selectedTab = .settings
                appStateManager.settingsRoute = .serverSettings
            } label: {
                Text(LanguageManager.shared.localized("Go to Server Settings"))
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
