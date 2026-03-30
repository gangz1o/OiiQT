import SwiftUI

struct ServerMenuSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: ServerType

    init(server: ServerConfig) {
        self.id = server.id
        let trimmedName = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? server.type.rawValue : trimmedName
        self.type = server.type
    }
}

struct ServerDropdownMenuView: View, Equatable {
    let activeServerType: ServerType?
    let activeServerID: UUID?
    let serverMenuSnapshots: [ServerMenuSnapshot]
    let canUseGlobalTaskAggregation: Bool
    let isDisabled: Bool
    let onSelectServer: (UUID?) -> Void

    static func == (lhs: ServerDropdownMenuView, rhs: ServerDropdownMenuView) -> Bool {
        lhs.activeServerType == rhs.activeServerType &&
        lhs.activeServerID == rhs.activeServerID &&
        lhs.serverMenuSnapshots == rhs.serverMenuSnapshots &&
        lhs.canUseGlobalTaskAggregation == rhs.canUseGlobalTaskAggregation &&
        lhs.isDisabled == rhs.isDisabled
    }

    var body: some View {
        Menu {
            if canUseGlobalTaskAggregation {
                Button {
                    onSelectServer(nil)
                } label: {
                    Label(LanguageManager.shared.localized("All Servers"), systemImage: "rectangle.stack.fill")
                }
            }

            ForEach(serverMenuSnapshots) { snapshot in
                Button {
                    onSelectServer(snapshot.id)
                } label: {
                    HStack(spacing: 10) {
                        ServerBrandIcon(type: snapshot.type, size: 20)

                        Text(snapshot.name)
                    }
                }
            }
        } label: {
            ServerBrandIcon(type: activeServerType, size: 22)
        }
        .disabled(isDisabled)
        .animation(nil, value: serverMenuSnapshots)
        .zIndex(100)
    }
}
