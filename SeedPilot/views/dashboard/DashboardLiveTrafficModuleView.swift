//
//  DashboardLiveTrafficModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/17.
//

import SwiftUI

struct DashboardLiveTrafficModuleView: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    var body: some View {
        LazyVGrid(columns: DashboardGrid.columns, spacing: 12) {
            // 性能优化：使用 EquatableView 包裹，高频速度更新仅触发文本局部刷新
            EquatableView(content: DashboardTrafficTile(
                value: formatBytes(downloadSpeed),
                icon: "arrow.down.circle.fill",
                tint: .blue
            ))

            EquatableView(content: DashboardTrafficTile(
                value: formatBytes(uploadSpeed),
                icon: "arrow.up.circle.fill",
                tint: .green
            ))
        }
    }
}

// 性能优化：遵循 Equatable，配合 EquatableView 实现状态隔离
private struct DashboardTrafficTile: View, Equatable {
    let value: String
    let icon: String
    let tint: Color

    static func == (lhs: DashboardTrafficTile, rhs: DashboardTrafficTile) -> Bool {
        lhs.value == rhs.value && lhs.icon == rhs.icon && lhs.tint == rhs.tint
    }

    var body: some View {
        DashboardTile {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text("/s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
