import SwiftUI

private struct RefreshDeferringScrollModifier: ViewModifier {
    @Environment(AppStateManager.self) private var appStateManager
    let name: String

    @State private var sourceID = UUID()

    private var sourceKey: String {
        "\(name)#\(sourceID.uuidString)"
    }

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, newPhase in
                appStateManager.setRefreshSuspension(newPhase.isScrolling, source: sourceKey)
            }
            .onDisappear {
                appStateManager.setRefreshSuspension(false, source: sourceKey)
            }
    }
}

extension View {
    func defersAppRefreshWhileScrolling(_ name: String) -> some View {
        modifier(RefreshDeferringScrollModifier(name: name))
    }
}
