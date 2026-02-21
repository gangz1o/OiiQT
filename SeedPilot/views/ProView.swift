//
//  ProView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/15.
//

import SwiftUI
import StoreKit
import UIKit

struct ProView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var selectedOption: Int = 0
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var purchaseErrorMessage: String?
    @State private var showingPurchaseError = false
    @State private var showSuccessFeedback = false
    @State private var showingPrivacyPolicySheet = false
    @State private var showingTermsSheet = false
    @AppStorage("isProUser") private var isProUser = false

    private let optionProductIDs = [
        "com.seedpilot.pro.lifetime",
        "com.seedpilot.pro.yearly",
        "com.seedpilot.pro.monthly"
    ]

    var body: some View {
        ZStack {
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await storeManager.fetchProducts()
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

    private var successOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text(LanguageManager.shared.localized("Thank You!"))
                .font(.title.bold())
            Text(LanguageManager.shared.localized("SeedPilot Pro has been activated."))
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
        VStack(spacing: 10) {
            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)

            Text("SeedPilot Pro")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

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
        .padding(.top, 20)
        .padding(.horizontal, 16)
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
        VStack(spacing: 16) {
            if storeManager.products.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(LanguageManager.shared.localized("Verifying subscription status..."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            optionCard(
                index: 0,
                title: LanguageManager.shared.localized("Lifetime Purchase"),
                subtitle: LanguageManager.shared.localized("Early bird special, pay once and unlock forever"),
                price: priceText(for: optionProductIDs[0], fallback: "¥69.00"),
                badge: LanguageManager.shared.localized("Limited Early Bird")
            )

            optionCard(
                index: 1,
                title: LanguageManager.shared.localized("Yearly Subscription"),
                subtitle: LanguageManager.shared.localized("Equivalent to ¥6.00 / month"),
                price: priceText(for: optionProductIDs[1], fallback: LanguageManager.shared.localized("¥72.00 / year"))
            )

            optionCard(
                index: 2,
                title: LanguageManager.shared.localized("Monthly Subscription"),
                subtitle: nil,
                price: priceText(for: optionProductIDs[2], fallback: LanguageManager.shared.localized("¥6.00 / month"))
            )
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
                .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1.5)
                )

                if let badge = badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
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
                        .tint(.white)
                } else {
                    Text(LanguageManager.shared.localized("Unlock Now"))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.blue)
            .clipShape(Capsule())
            .shadow(color: .blue.opacity(0.22), radius: 8, x: 0, y: 4)
        }
        .disabled(isPurchasing || selectedProduct == nil)
        .padding(.horizontal, 16)
    }

    private var selectedProductID: String {
        let safeIndex = min(max(selectedOption, 0), optionProductIDs.count - 1)
        return optionProductIDs[safeIndex]
    }

    private var selectedProduct: Product? {
        storeManager.products.first { $0.id == selectedProductID }
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

    private func priceText(for productID: String, fallback: String) -> String {
        storeManager.products.first(where: { $0.id == productID })?.displayPrice ?? fallback
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

#Preview {
    NavigationStack {
        ProView()
    }
}
