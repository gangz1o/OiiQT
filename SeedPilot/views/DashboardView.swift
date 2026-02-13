//
//  DashboardView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI
import Charts
import Combine

// MARK: - Models for Chart
struct NetworkSpeed: Identifiable {
    let id = UUID()
    let time: Date
    let downloadSpeed: Double // MB/s
    let uploadSpeed: Double   // MB/s
}

struct DashboardView: View {
    // 模拟数据
    @State private var speedData: [NetworkSpeed] = []
    @State private var downloadCount = 12
    @State private var seedingCount = 45
    @State private var diskUsed: Double = 3.2 // TB
    @State private var diskTotal: Double = 8.0 // TB
    
    // 定时器模拟实时数据
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 速度图表卡片
                    speedChartCard
                    
                    // 2. 状态统计卡片 (并排)
                    HStack(spacing: 16) {
                        statusCard(
                            title: "正在下载",
                            count: downloadCount,
                            icon: "arrow.down.circle.fill",
                            color: .blue
                        )
                        
                        statusCard(
                            title: "正在做种",
                            count: seedingCount,
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                    }
                    
                    // 3. 磁盘空间卡片
                    diskSpaceCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("仪表盘")
            .onAppear {
                generateInitialData()
            }
            .onReceive(timer) { _ in
                updateData()
            }
        }
    }
    
    // MARK: - Components
    
    // 1. 速度图表卡片
    private var speedChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("网络速度", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            Chart {
                ForEach(speedData) { item in
                    // 下载速度曲线
                    LineMark(
                        x: .value("时间", item.time),
                        y: .value("下载", item.downloadSpeed),
                        series: .value("类型", "下载")
                    )
                    .foregroundStyle(.blue.gradient)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("时间", item.time),
                        y: .value("下载", item.downloadSpeed),
                        series: .value("类型", "下载")
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    // 上传速度曲线
                    LineMark(
                        x: .value("时间", item.time),
                        y: .value("上传", item.uploadSpeed),
                        series: .value("类型", "上传")
                    )
                    .foregroundStyle(.green.gradient)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("时间", item.time),
                        y: .value("上传", item.uploadSpeed),
                        series: .value("类型", "上传")
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.green.opacity(0.3), .green.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: speedData.map { $0.downloadSpeed })
            
            // 图例和当前速度
            HStack(spacing: 20) {
                if let last = speedData.last {
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                        Text("↓ \(String(format: "%.1f", last.downloadSpeed)) MB/s")
                            .font(.caption).bold()
                            .foregroundStyle(.blue)
                            .contentTransition(.numericText(value: last.downloadSpeed))
                    }
                    
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("↑ \(String(format: "%.1f", last.uploadSpeed)) MB/s")
                            .font(.caption).bold()
                            .foregroundStyle(.green)
                            .contentTransition(.numericText(value: last.uploadSpeed))
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // 2. 状态统计卡片
    private func statusCard(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: count)
            }
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // 3. 磁盘空间卡片
    private var diskSpaceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("存储空间", systemImage: "externaldrive")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 24) {
                // 进度环
                Gauge(value: diskUsed, in: 0...diskTotal) {
                    Text("使用率")
                } currentValueLabel: {
                    Text("\(Int((diskUsed / diskTotal) * 100))%")
                        .font(.caption)
                        .contentTransition(.numericText(value: diskUsed))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.orange)
                .scaleEffect(1.2)
                .frame(width: 60, height: 60)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: diskUsed)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("已用: \(String(format: "%.1f", diskUsed)) TB")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText(value: diskUsed))
                        Spacer()
                    }
                    
                    HStack {
                        Text("总计: \(String(format: "%.1f", diskTotal)) TB")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    ProgressView(value: diskUsed, total: diskTotal)
                        .tint(.orange)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: diskUsed)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helpers
    
    private func generateInitialData() {
        let now = Date()
        speedData = (0..<20).map { i in
            NetworkSpeed(
                time: now.addingTimeInterval(Double(-i)),
                downloadSpeed: Double.random(in: 2.0...15.0),
                uploadSpeed: Double.random(in: 0.5...5.0)
            )
        }.reversed()
    }
    
    private func updateData() {
        withAnimation(.easeInOut) {
            let config = speedData.last ?? NetworkSpeed(time: Date(), downloadSpeed: 0, uploadSpeed: 0)
            
            // 模拟波动
            let newDownload = max(0, config.downloadSpeed + Double.random(in: -3.0...3.0))
            let newUpload = max(0, config.uploadSpeed + Double.random(in: -1.0...1.0))
            
            let newData = NetworkSpeed(
                time: Date(),
                downloadSpeed: newDownload,
                uploadSpeed: newUpload
            )
            
            if speedData.count >= 20 {
                speedData.removeFirst()
            }
            speedData.append(newData)
        }
    }
}

#Preview {
    DashboardView()
}
