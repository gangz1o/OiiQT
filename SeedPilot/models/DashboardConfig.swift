//
//  DashboardConfig.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

final class DashboardConfig {
    static let shared = DashboardConfig()

    enum Keys {
        static let showTodayTransfer = "dashboard.showTodayTransfer"
        static let showRecentFinished = "dashboard.showRecentFinished"
        static let showLiveTraffic = "dashboard.showLiveTraffic"
        static let showGlobalAssets = "dashboard.showGlobalAssets"
        static let showServerStatus = "dashboard.showServerStatus"
        static let showStorageAudit = "dashboard.showStorageAudit"
        static let moduleOrder = "dashboard.moduleOrder"
    }

    @AppStorage(Keys.showTodayTransfer) var showTodayTransfer: Bool = true
    @AppStorage(Keys.showRecentFinished) var showRecentFinished: Bool = true
    @AppStorage(Keys.showLiveTraffic) var showLiveTraffic: Bool = true
    @AppStorage(Keys.showGlobalAssets) var showGlobalAssets: Bool = true
    @AppStorage(Keys.showServerStatus) var showServerStatus: Bool = true
    @AppStorage(Keys.showStorageAudit) var showStorageAudit: Bool = true

    var showTodayTransferBinding: Binding<Bool> {
        Binding(
            get: { self.showTodayTransfer },
            set: { self.showTodayTransfer = $0 }
        )
    }

    var showRecentFinishedBinding: Binding<Bool> {
        Binding(
            get: { self.showRecentFinished },
            set: { self.showRecentFinished = $0 }
        )
    }

    var showLiveTrafficBinding: Binding<Bool> {
        Binding(
            get: { self.showLiveTraffic },
            set: { self.showLiveTraffic = $0 }
        )
    }

    var showGlobalAssetsBinding: Binding<Bool> {
        Binding(
            get: { self.showGlobalAssets },
            set: { self.showGlobalAssets = $0 }
        )
    }

    var showServerStatusBinding: Binding<Bool> {
        Binding(
            get: { self.showServerStatus },
            set: { self.showServerStatus = $0 }
        )
    }

    var showStorageAuditBinding: Binding<Bool> {
        Binding(
            get: { self.showStorageAudit },
            set: { self.showStorageAudit = $0 }
        )
    }
}
