//
//  DashboardModuleType.swift
//  OiiQT
//
//  Created by Codex on 2026/2/18.
//

import Foundation

enum DashboardModuleType: String, CaseIterable, Identifiable {
    case proPosterWall
    case liveTraffic
    case todayTransfer
    case globalAssets
    case serverStatus
    case storageAudit
    case recentFinished

    var id: String { rawValue }

    static let defaultOrder: [DashboardModuleType] = [
        .proPosterWall,
        .liveTraffic,
        .todayTransfer,
        .globalAssets,
        .serverStatus,
        .storageAudit,
        .recentFinished
    ]
}
