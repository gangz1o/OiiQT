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
            case .monthly: return LanguageManager.shared.localized("Monthly Subscription")
            case .yearly: return LanguageManager.shared.localized("Yearly Subscription")
            case .lifetime: return LanguageManager.shared.localized("Lifetime Purchase")
            }
        }

        var price: String {
            switch self {
            case .monthly: return LanguageManager.shared.localized("¥6.00 / month")
            case .yearly: return LanguageManager.shared.localized("¥58.00 / year")
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

                Text(LanguageManager.shared.localized("Unlock a premium visual experience and take control of your media world."))
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
            featureRow(icon: "movieclapper.fill", color: .purple, title: LanguageManager.shared.localized("TMDB Poster Wall"), desc: LanguageManager.shared.localized("Automatically match high-quality movie posters and cinematic backdrops."))
            Divider()
            featureRow(icon: "chart.bar.doc.horizontal.fill", color: .blue, title: LanguageManager.shared.localized("Pro Dynamic Dashboard"), desc: LanguageManager.shared.localized("Show recently finished tasks with elegant dynamic carousels."))
            Divider()
            featureRow(icon: "heart.fill", color: .red, title: LanguageManager.shared.localized("Support Independent Development"), desc: LanguageManager.shared.localized("Help SeedPilot continue shipping improvements."))
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
            planButton(type: .yearly, badge: LanguageManager.shared.localized("Recommended / Save 50%"))

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if type == .yearly {
                            Text(LanguageManager.shared.localized("Equivalent to ¥4.83 / month"))
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
                Text(String(format: LanguageManager.shared.localized("Subscribe Now (%@)"), selectedPlan.priceValue))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 32)

            Button(LanguageManager.shared.localized("Restore Purchases")) {
                // Restore action
            }
            .font(.subheadline)
            .foregroundStyle(.blue)

            Text(LanguageManager.shared.localized("Payment will be charged to your Apple ID upon confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period."))
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
