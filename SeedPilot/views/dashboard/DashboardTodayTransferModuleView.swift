//
//  DashboardTodayTransferModuleView.swift
//  SeedPilot
//
//  Created by Codex on 2026/2/24.
//

import Foundation
import SwiftUI
import Charts

struct DashboardTodayTransferModuleView: View {
    let uploadData: [TrackerTransferData]
    let downloadData: [TrackerTransferData]
    var isInitialLoading: Bool = false

    @State private var selectedType: TransferType = .upload
    @State private var selectedTrackerStat: TrackerTransferData?
    @State private var selectionResetTimer: Timer?

    private var selectionBinding: Binding<TransferType> {
        Binding(
            get: { selectedType },
            set: { newValue in
                guard newValue != selectedType else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    selectedType = newValue
                }
            }
        )
    }

    private var currentData: [TrackerTransferData] {
        switch selectedType {
        case .upload:
            return uploadData
        case .download:
            return downloadData
        }
    }

    private var totalBytes: Int64 {
        currentData.reduce(0) { $0 + max($1.bytes, 0) }
    }

    private var hasTransferData: Bool {
        totalBytes > 0
    }

    private var showsInitialLoadingState: Bool {
        isInitialLoading && uploadData.isEmpty && downloadData.isEmpty
    }

    private var activeSelectedTrackerStat: TrackerTransferData? {
        guard let selectedTrackerStat else { return nil }
        return currentData.first(where: { $0.id == selectedTrackerStat.id })
    }

    private var emptyStateMessage: String {
        switch selectedType {
        case .upload:
            return LanguageManager.shared.localized("今日暂无上传数据")
        case .download:
            return LanguageManager.shared.localized("今日暂无下载数据")
        }
    }

    private var centerPrimaryText: String {
        activeSelectedTrackerStat?.trackerName ?? LanguageManager.shared.localized("总计")
    }

    private var centerValueText: String {
        if let selected = activeSelectedTrackerStat {
            return formattedChartBytes(selected.bytes)
        }
        return formattedChartBytes(totalBytes)
    }

    var body: some View {
        DashboardTile(minHeight: 360) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Spacer(minLength: 0)
                    Picker("", selection: selectionBinding) {
                        ForEach(TransferType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }

                Group {
                    if showsInitialLoadingState {
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.regular)

                            Text(LanguageManager.shared.localized("Loading..."))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
                        )
                        .transition(.opacity)
                    } else if hasTransferData {
                        Chart(currentData) { item in
                            SectorMark(
                                angle: .value(LanguageManager.shared.localized("传输量"), max(Double(item.bytes), 0)),
                                innerRadius: .ratio(0.65),
                                angularInset: 2
                            )
                            .foregroundStyle(item.color)
                        }
                        .chartLegend(.hidden)
                        .chartBackground { proxy in
                            GeometryReader { geometry in
                                if let anchor = proxy.plotFrame {
                                    let frame = geometry[anchor]
                                    VStack(spacing: 2) {
                                        Text(centerPrimaryText)
                                            .font(activeSelectedTrackerStat == nil ? .caption : .caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)

                                        Text(centerValueText)
                                            .font(.system(.title2, design: .rounded).weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .frame(maxWidth: frame.width * 0.5)
                                    .position(x: frame.midX, y: frame.midY)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clearSelectedTracker(animated: true)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.pie")
                                .font(.system(size: 26, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.tertiary)

                            Text(emptyStateMessage)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
                        )
                        .transition(.opacity)
                    }
                }
                .frame(height: 230)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: selectedType)
                .animation(.easeInOut(duration: 0.2), value: hasTransferData)
                .animation(.easeInOut(duration: 0.2), value: showsInitialLoadingState)

                if hasTransferData {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(currentData) { item in
                                legendChip(for: item)
                                    .onTapGesture {
                                        selectTracker(item)
                                    }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: selectedType) { _, _ in
            clearSelectedTracker(animated: false)
        }
        .onDisappear {
            invalidateSelectionResetTimer()
        }
    }

    private func legendChip(for item: TrackerTransferData) -> some View {
        let isSelected = activeSelectedTrackerStat?.id == item.id

        return HStack(spacing: 6) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)

            Text(item.trackerName)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(percentageText(for: item))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isSelected ? item.color.opacity(0.14) : Color(uiColor: .tertiarySystemFill))
        .overlay(
            Capsule()
                .stroke(isSelected ? item.color.opacity(0.35) : .clear, lineWidth: 0.8)
        )
        .clipShape(Capsule())
    }

    private func percentageText(for item: TrackerTransferData) -> String {
        guard totalBytes > 0 else { return "0%" }
        let value = (Double(item.bytes) / Double(totalBytes)) * 100
        return value >= 10 ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }

    private func selectTracker(_ item: TrackerTransferData) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTrackerStat = item
        }
        scheduleSelectionResetTimer()
    }

    private func clearSelectedTracker(animated: Bool) {
        invalidateSelectionResetTimer()
        let update = { selectedTrackerStat = nil }
        if animated {
            withAnimation(.easeInOut(duration: 0.2), update)
        } else {
            update()
        }
    }

    private func scheduleSelectionResetTimer() {
        invalidateSelectionResetTimer()
        selectionResetTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            clearSelectedTracker(animated: true)
        }
    }

    private func invalidateSelectionResetTimer() {
        selectionResetTimer?.invalidate()
        selectionResetTimer = nil
    }

    private func formattedChartBytes(_ bytes: Int64) -> String {
        Self.chartByteFormatter.string(fromByteCount: max(bytes, 0))
    }
}

private extension DashboardTodayTransferModuleView {
    static let chartByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.isAdaptive = false
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    enum TransferType: String, CaseIterable, Identifiable {
        case upload
        case download

        var id: String { rawValue }

        var title: String {
            switch self {
            case .upload:
                return LanguageManager.shared.localized("Upload")
            case .download:
                return LanguageManager.shared.localized("Download")
            }
        }
    }
}
