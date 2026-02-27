//
//  ProView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI
import StoreKit

struct ProView: View {
    struct ProFeature: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State var selectedOption: Int = 0
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var purchaseErrorMessage: String?
    @State private var showingPurchaseError = false
    @State private var showSuccessFeedback = false
    @State private var isAnimating = false
    @State private var showingPrivacyPolicySheet = false
    @State private var showingTermsSheet = false
    @AppStorage("isProUser") private var isProUser = false

    private let optionProductIDs = [
        "com.seedpilot.pro.lifetime",
        "com.seedpilot.yearly.pro",
        "com.seedpilot.monthly.pro"
    ]

    private let proFeatures: [ProFeature] = [
        ProFeature(
            icon: "film.fill",
            color: .pink,
            title: "影视海报与元数据",
            subtitle: "自动匹配高清海报与剧情简介，无缝适配您的系统语言。"
        ),
        ProFeature(
            icon: "photo.stack.fill",
            color: .blue,
            title: "动态海报墙",
            subtitle: "在仪表盘以精美轮播图展示您最近添加的影视收藏。"
        ),
        ProFeature(
            icon: "server.rack",
            color: .teal,
            title: "全局任务聚合",
            subtitle: "在同一列表中集中展示并管理所有服务器的种子任务。"
        ),
        ProFeature(
            icon: "tag.fill",
            color: .purple,
            title: "Tracker 别名",
            subtitle: "为冗长的 Tracker 域名设置个性化短名称，告别排版杂乱。"
        ),
        ProFeature(
            icon: "heart.fill",
            color: .red,
            title: "支持独立开发",
            subtitle: "助力 Downix 持续迭代更新，解锁未来所有专属功能。"
        )
    ]

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                auroraBackground

                ScrollView {
                    VStack(spacing: 32) {
                        // 1. Hero Header
                        headerSection

                        // 2. Features List
                        featuresSection

                        // 3. Pricing Tiers
                        if isProUser {
                            proStatusSection
                        } else {
                            pricingSection
                            inlineUnlockButton
                        }

                        // 4. Compliance Footer
                        complianceFooterSection

                        Spacer().frame(height: 24)
                    }
                    .padding(.bottom, 20)
                }

                if showSuccessFeedback {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .zIndex(1)

                    successOverlay
                        .frame(maxHeight: .infinity, alignment: .center)
                        .zIndex(2)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await storeManager.fetchProducts()
        }
        .onAppear {
            guard !isAnimating else { return }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .alert(LanguageManager.shared.localized("Error"), isPresented: $showingPurchaseError) {
            Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
        } message: {
            Text(purchaseErrorMessage ?? LanguageManager.shared.localized("Unknown Error"))
        }
        .sheet(isPresented: $showingPrivacyPolicySheet) {
            PrivacyPolicySheetView()
        }
        .sheet(isPresented: $showingTermsSheet) {
            TermsOfServiceSheetView()
        }
    }

    // MARK: - Sections

    private var auroraBackground: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: auroraLinearColors,
                    startPoint: isAnimating ? .topTrailing : .topLeading,
                    endPoint: isAnimating ? .bottomLeading : .bottomTrailing
                )

                AngularGradient(
                    colors: auroraAngularColors,
                    center: .center,
                    angle: .degrees(isAnimating ? 220 : 40)
                )
                .blendMode(.screen)
                .opacity(colorScheme == .dark ? 0.72 : 0.55)
            }
            .frame(height: proxy.size.height * 0.55)
            .mask(
                LinearGradient(
                    colors: [.black, .black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: isAnimating)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private var auroraLinearColors: [Color] {
        if colorScheme == .dark {
            return [
                .black,
                .purple.opacity(0.6),
                .blue.opacity(0.5),
                .black
            ]
        }
        return [
            Color(uiColor: .systemBackground),
            .purple.opacity(0.18),
            .blue.opacity(0.16),
            Color(uiColor: .systemBackground)
        ]
    }

    private var auroraAngularColors: [Color] {
        if colorScheme == .dark {
            return [
                .black.opacity(0.9),
                .purple.opacity(0.35),
                .blue.opacity(0.3),
                .black.opacity(0.9)
            ]
        }
        return [
            Color(uiColor: .systemBackground).opacity(0.95),
            .purple.opacity(0.12),
            .blue.opacity(0.12),
            Color(uiColor: .systemBackground).opacity(0.95)
        ]
    }

    private var successOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text(LanguageManager.shared.localized("Thank You!"))
                .font(.title.bold())
            Text(LanguageManager.shared.localized("Downix Pro has been activated."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(showSuccessFeedback ? 1 : 0.8)
        .opacity(showSuccessFeedback ? 1 : 0)
        .padding(.horizontal, 32)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("DownixProHeader")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 340, height: 120)
                .clipped()
                .accessibilityHidden(true)

            Text(
                isProUser
                ? heroSubtitleText
                : LanguageManager.shared.localized("Unlock a premium visual experience and take control of your media world.")
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.horizontal, 16)
    }

    private var featuresSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(proFeatures.enumerated()), id: \.element.id) { index, feature in
                    featureRow(feature)
                        .padding(.vertical, 8)

                    if index < proFeatures.count - 1 {
                        Divider()
                            .overlay(Color.secondary.opacity(0.18))
                            .padding(.leading, 40)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }

    private func featureRow(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundStyle(feature.color)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.subheadline.bold())
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }

    private var pricingSection: some View {
        VStack(spacing: 16) {
            if storeManager.isSubscriptionStatusLoading && storeManager.products.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(LanguageManager.shared.localized("Verifying subscription status..."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            if !orderedProducts.isEmpty {
                ForEach(Array(orderedProducts.enumerated()), id: \.element.id) { index, product in
                    optionCard(
                        index: index,
                        title: product.displayName,
                        subtitle: subtitleText(for: product),
                        price: product.displayPrice,
                        badge: badgeText(for: product)
                    )
                }
            } else if !storeManager.isSubscriptionStatusLoading {
                Text(LanguageManager.shared.localized("Unable to load purchase options. Please check your network and try again."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedOption)
    }

    private var proStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proStatusTitleText)
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(proStatusSubtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func optionCard(index: Int, title: String, subtitle: String?, price: String, badge: String? = nil) -> some View {
        let isSelected = selectedOption == index

        return Button {
            selectedOption = index
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(isSelected ? .blue : .primary)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(price)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(isSelected ? .blue : .primary)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.blue : Color.gray)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.blue.opacity(0.1) : .clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1.5)
                )

                if let badge = badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red))
                        .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var complianceFooterSection: some View {
        VStack(spacing: 16) {
            if isProUser {
                Button(LanguageManager.shared.localized("Manage Subscription")) {
                    guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
                    openURL(url)
                }
                .font(.footnote)
                .bold()
                .foregroundStyle(.blue)
                .padding(.top, 8)
            }

            Button(LanguageManager.shared.localized("Restore Purchases")) {
                Task {
                    await storeManager.restorePurchases()
                }
            }
            .font(.footnote)
            .bold()
            .foregroundStyle(.blue)
            .padding(.top, 8)

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Privacy Policy")) {
                    showingPrivacyPolicySheet = true
                }
                .buttonStyle(.plain)
                Text("|")
                Button(LanguageManager.shared.localized("Terms of Service")) {
                    showingTermsSheet = true
                }
                .buttonStyle(.plain)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var inlineUnlockButton: some View {
        Button {
            Task {
                await purchaseSelectedProduct()
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(Color(uiColor: .systemBackground))
                } else {
                    Text(LanguageManager.shared.localized("Unlock Now"))
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.primary)
            .clipShape(Capsule())
            .shadow(color: .primary.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .disabled(isPurchasing || selectedProduct == nil)
        .padding(.horizontal, 16)
    }

    private var orderedProducts: [Product] {
        let order = Dictionary(uniqueKeysWithValues: optionProductIDs.enumerated().map { ($1, $0) })
        return storeManager.products.sorted { lhs, rhs in
            (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
        }
    }

    private var selectedProduct: Product? {
        guard !orderedProducts.isEmpty else { return nil }
        let safeIndex = min(max(selectedOption, 0), orderedProducts.count - 1)
        return orderedProducts[safeIndex]
    }

    private var heroSubtitleText: String {
        if storeManager.isLifetime {
            return LanguageManager.shared.localized("Thank you for your long-term support")
        }
        return LanguageManager.shared.localized("Thank you for your subscription")
    }

    private var proStatusTitleText: String {
        if storeManager.isLifetime {
            return LanguageManager.shared.localized("Lifetime Pro Benefits")
        }
        if storeManager.expirationDate != nil {
            return LanguageManager.shared.localized("Pro Subscription Active")
        }
        return LanguageManager.shared.localized("Pro Benefits")
    }

    private var proStatusSubtitleText: String {
        if storeManager.isLifetime {
            return LanguageManager.shared.localized("All premium features are permanently unlocked")
        }
        if let formattedDate = formattedExpirationDate {
            return String(format: String(localized: "Benefits expire on %@"), formattedDate)
        }
        return LanguageManager.shared.localized("All Pro features unlocked")
    }

    private var formattedExpirationDate: String? {
        guard let date = storeManager.expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func subtitleText(for product: Product) -> String? {
        switch product.id {
        case "com.seedpilot.pro.lifetime":
            return LanguageManager.shared.localized("Early bird special, pay once and unlock forever")
        default:
            return nil
        }
    }

    private func badgeText(for product: Product) -> String? {
        product.id == "com.seedpilot.pro.lifetime"
            ? LanguageManager.shared.localized("Limited Early Bird")
            : nil
    }

    @MainActor
    private func purchaseSelectedProduct() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await storeManager.purchase(product)
            guard storeManager.lastPurchaseSucceeded else { return }
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showSuccessFeedback = true
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            dismiss()
        } catch {
            purchaseErrorMessage = error.localizedDescription
            showingPurchaseError = true
        }
    }
}

#Preview("Light") {
    NavigationStack {
        ProView()
    }
}

#Preview("Dark") {
    NavigationStack {
        ProView()
    }
    .preferredColorScheme(.dark)
}
