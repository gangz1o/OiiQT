import Foundation
import StoreKit
import Combine

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let hidesReviewSensitiveFeatures = true

    private let lifetimeProductID = "com.oiiqt.lifetime.pro"

    let productIDs = [
        "com.oiiqt.lifetime.pro",
        "com.oiiqt.yearly.pro",
        "com.oiiqt.monthly.pro"
    ]

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isProUser = false
    @Published var isLifetime = false
    @Published var expirationDate: Date?
    @Published var lastPurchaseSucceeded = false
    @Published private(set) var isSubscriptionStatusLoading = false

    private var updatesTask: Task<Void, Never>?
    private var subscriptionStatusLoadingDepth = 0

    private init() {
        updatesTask = startTransactionListener()

        Task {
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func fetchProducts() async {
        beginSubscriptionStatusLoading()
        defer { endSubscriptionStatusLoading() }

        do {
            let fetched = try await Product.products(for: productIDs)
            if fetched.isEmpty {
                print("ERROR StoreManager fetchProducts returned empty product list. Expected IDs: \(productIDs)")
            } else {
                let fetchedIDs = Set(fetched.map(\.id))
                let missingIDs = productIDs.filter { !fetchedIDs.contains($0) }
                if !missingIDs.isEmpty {
                    print("ERROR StoreManager fetchProducts missing products for IDs: \(missingIDs). Fetched IDs: \(Array(fetchedIDs))")
                }
            }
            let order = Dictionary(uniqueKeysWithValues: productIDs.enumerated().map { ($1, $0) })
            products = fetched.sorted { lhs, rhs in
                let leftOrder = order[lhs.id] ?? Int.max
                let rightOrder = order[rhs.id] ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return lhs.price > rhs.price
            }
            await updateCustomerProductStatus()
        } catch {
            print("ERROR StoreManager fetchProducts failed: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        lastPurchaseSucceeded = false

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateCustomerProductStatus()
            lastPurchaseSucceeded = isProUser
        case .pending:
            break
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        beginSubscriptionStatusLoading()
        defer { endSubscriptionStatusLoading() }

        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
        } catch {
            print("StoreManager restorePurchases failed: \(error)")
        }
    }

    func updateCustomerProductStatus() async {
        beginSubscriptionStatusLoading()
        defer { endSubscriptionStatusLoading() }

        // Rebuild entitlement state off-screen and commit once, so observers
        // never see a transient "non-Pro" value during foreground refresh.
        var purchased = Set<String>()
        var hasProAccess = false
        var hasLifetimeAccess = false
        var latestExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let entitlementExpirationDate = transaction.expirationDate, entitlementExpirationDate < Date() {
                continue
            }

            purchased.insert(transaction.productID)
            hasProAccess = true

            if transaction.productID == lifetimeProductID {
                hasLifetimeAccess = true
                latestExpirationDate = nil
                continue
            }

            if !hasLifetimeAccess, let entitlementExpirationDate = transaction.expirationDate {
                latestExpirationDate = max(latestExpirationDate ?? entitlementExpirationDate, entitlementExpirationDate)
            }
        }

        purchasedProductIDs = purchased
        isProUser = hasProAccess
        isLifetime = hasLifetimeAccess
        expirationDate = hasLifetimeAccess ? nil : latestExpirationDate
        setProUnlocked(hasProAccess)
    }

    private func startTransactionListener() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(verification)
            }
        }
    }

    private func handleTransactionUpdate(_ verification: VerificationResult<Transaction>) async {
        switch verification {
        case .verified(let transaction):
            await transaction.finish()
        case .unverified:
            print("ERROR StoreManager received unverified transaction update")
            break
        }
        await updateCustomerProductStatus()
    }

    private func setProUnlocked(_ value: Bool) {
        isProUser = value
        UserDefaults.standard.set(value, forKey: "isProUser")
        if !value {
            disableAllProFeatureFlags()
        }
    }

    private func disableAllProFeatureFlags() {
        let defaults = UserDefaults.standard
        let wasTMDBEnabled = defaults.bool(forKey: "showTMDBData")
        let wasLegacyTMDBEnabled = defaults.bool(forKey: "tmdbPosterEnabled")
        let wasGlobalTaskAggregationEnabled = defaults.bool(forKey: "enableGlobalTaskAggregation")
        let wasDashboardProEnabled = defaults.bool(forKey: "proDashboardBackgroundEnabled")
        let wasICloudSyncEnabled = defaults.bool(forKey: "iCloudSyncEnabled")

        guard wasTMDBEnabled || wasLegacyTMDBEnabled || wasGlobalTaskAggregationEnabled || wasDashboardProEnabled || wasICloudSyncEnabled else {
            return
        }

        defaults.set(false, forKey: "showTMDBData")
        defaults.set(false, forKey: "tmdbPosterEnabled")
        defaults.set(false, forKey: "enableGlobalTaskAggregation")
        defaults.set(false, forKey: "proDashboardBackgroundEnabled")
        defaults.set(false, forKey: "iCloudSyncEnabled")

        // Ensure iCloud sync worker is also turned off, not just the persisted flag.
        if wasICloudSyncEnabled {
            iCloudSyncManager.shared.setSyncEnabled(false)
        }
    }

    private func beginSubscriptionStatusLoading() {
        subscriptionStatusLoadingDepth += 1
        isSubscriptionStatusLoading = true
    }

    private func endSubscriptionStatusLoading() {
        subscriptionStatusLoadingDepth = max(0, subscriptionStatusLoadingDepth - 1)
        isSubscriptionStatusLoading = subscriptionStatusLoadingDepth > 0
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signedType):
            return signedType
        case .unverified(_, _):
            throw StoreError.failedVerification
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed."
        }
    }
}
