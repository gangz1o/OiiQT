//
//  TransfersView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

struct TransfersView: View {
    @Environment(AppStateManager.self) private var appStateManager
    
    // 状态筛选
    @State private var selectedStatus: String = "全部"
    let statusOptions = ["全部"] + TorrentStatus.allCases.map { $0.rawValue }
    
    // 添加磁力链接
    @State private var showingAddMagnet = false
    @State private var magnetLink = ""
    
    // 筛选后的任务列表
    var filteredTasks: [TorrentTask] {
        if selectedStatus == "全部" {
            return appStateManager.allTasks
        } else {
            return appStateManager.allTasks.filter { $0.status.rawValue == selectedStatus }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // 1. 任务列表
                    if filteredTasks.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(filteredTasks) { task in
                                TaskRow(task: task)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            appStateManager.deleteTasks([task])
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if task.status == .paused {
                                            Button {
                                                appStateManager.resumeTask(task)
                                            } label: {
                                                Label("恢复", systemImage: "play.fill")
                                            }
                                            .tint(.green)
                                        } else {
                                            Button {
                                                appStateManager.pauseTask(task)
                                            } label: {
                                                Label("暂停", systemImage: "pause.fill")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                
                // 2. 悬浮按钮 (FAB)
                Button {
                    showingAddMagnet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
                }
                .padding()
            }
            .navigationTitle(selectedStatus == "全部" ? "传输任务" : "\(selectedStatus)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("筛选状态", selection: $selectedStatus) {
                            ForEach(statusOptions, id: \.self) { status in
                                Text(status)
                                    .tag(status)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .alert("添加磁力链接", isPresented: $showingAddMagnet) {
                TextField("粘贴磁力链接", text: $magnetLink)
                Button("取消", role: .cancel) { }
                Button("添加") {
                    appStateManager.addMagnetLink(magnetLink)
                    magnetLink = ""
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无任务")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Task Row View
struct TaskRow: View {
    let task: TorrentTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 文件名
            Text(task.name)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
            
            // 进度条
            ProgressView(value: task.progress)
                .tint(task.status.color)
            
            // 详细信息 (大小 / 速度 / 时间)
            HStack {
                Text(task.sizeString)
                
                if task.status == .downloading || task.status == .seeding {
                    Text("•")
                    Text(task.speedString)
                        .foregroundStyle(task.status == .downloading ? .blue : .green)
                        .contentTransition(.numericText(value: Double(task.status == .seeding ? task.uploadSpeed : task.downloadSpeed)))
                }
                
                Spacer()
                
                // 状态文本或剩余时间
                if task.status == .downloading {
                    Text(remainingTimeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(task.status.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(task.status.color.opacity(0.1))
                        .foregroundStyle(task.status.color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .animation(.spring, value: task.progress) // Animate progress changes
    }
    
    private var remainingTimeString: String {
        if task.remainingTime < 0 { return "∞" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return "剩余 " + (formatter.string(from: task.remainingTime) ?? "--")
    }
}

#Preview {
    TransfersView()
        .environment(AppStateManager())
}
