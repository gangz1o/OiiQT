//
//  ProView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI

struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PlanType = .yearly

    enum PlanType {
        case monthly, yearly, lifetime

        var title: String {
            switch self {
            case .monthly: return "按月订阅"
            case .yearly: return "按年订阅"
            case .lifetime: return "终身买断"
            }
        }

        var price: String {
            switch self {
            case .monthly: return "¥6.00 / 月"
            case .yearly: return "¥58.00 / 年"
            case .lifetime: return "¥128.00"
            }
        }

        var priceValue: String {
            switch self {
            case .monthly: return "¥6.00"
            case .yearly: return "¥58.00"
            case .lifetime: return "¥128.00"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // 1. Hero Header
                headerSection

                // 2. Features List
                featuresSection

                // 3. Pricing Tiers
                pricingSection

                // 4. Footer Actions
                footerSection
            }
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Background Image (Mock Backdrop)
            Image(systemName: "movieclapper") // Placeholder if no real image
                .resizable()
                .scaledToFill()
                .frame(height: 300)
                .overlay {
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.8)
                }
                .overlay(.ultraThinMaterial)

            // Gradient Overlay for Text Readability
            LinearGradient(
                colors: [.clear, Color(uiColor: .systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)

            // Content
            VStack(spacing: 12) {
                Image("AppIcon") // Assuming AppIcon asset exists, or use system placeholder
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(radius: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )

                Text("SeedPilot Pro")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("解锁极致视觉体验，掌控你的影音世界。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .frame(height: 350)
    }

    private var featuresSection: some View {
        VStack(spacing: 20) {
            featureRow(icon: "movieclapper.fill", color: .purple, title: "TMDB 海报墙", desc: "自动匹配高清电影海报和大幅背景图。")
            Divider()
            featureRow(icon: "chart.bar.doc.horizontal.fill", color: .blue, title: "Pro 动态仪表盘", desc: "以精美轮播图展示最近完成的任务。")
            Divider()
            featureRow(icon: "heart.fill", color: .red, title: "支持独立开发", desc: "助力 SeedPilot 持续迭代更新。")
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var pricingSection: some View {
        VStack(spacing: 12) {
            // Yearly (Best Value)
            planButton(type: .yearly, badge: "最推荐 / 省 50%")

            // Monthly
            planButton(type: .monthly)

            // Lifetime
            planButton(type: .lifetime)
        }
        .padding(.horizontal, 16)
    }

    private func planButton(type: PlanType, badge: String? = nil) -> some View {
        Button {
            withAnimation {
                selectedPlan = type
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.title)
                            .font(.headline)
                            .foregroundStyle(selectedPlan == type ? .blue : .primary)

                        if type == .yearly {
                            Text("相当于 ¥4.83 / 月")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(type.price)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(selectedPlan == type ? .blue : .primary)

                    Image(systemName: selectedPlan == type ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedPlan == type ? Color.blue : Color.gray)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selectedPlan == type ? Color.blue : Color.clear, lineWidth: 2)
                )
                .shadow(color: selectedPlan == type ? Color.blue.opacity(0.1) : Color.clear, radius: 5)

                if let badge = badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var footerSection: some View {
        VStack(spacing: 16) {
            Button {
                // Action
            } label: {
                Text("立即订阅 (\(selectedPlan.priceValue))")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 32)

            Button("恢复购买") {
                // Restore action
            }
            .font(.subheadline)
            .foregroundStyle(.blue)

            Text("确认购买后，将向您的 Apple ID 账户收款。订阅会自动续期，除非在当前订阅期结束前至少 24 小时取消。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

#Preview {
    NavigationStack {
        ProView()
    }
}
