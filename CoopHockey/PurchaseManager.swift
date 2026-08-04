import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var localizedPrice: String?
    @Published private(set) var nemesisPrice: String?

    private var products: [String: Product] = [:]

    private init() {}

    private static let allProductIDs: Set<String> = [
        SettingsStore.removeAdsProductID,
        SettingsStore.nemesisProductID,
    ]

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            localizedPrice = products[SettingsStore.removeAdsProductID]?.displayPrice
            nemesisPrice   = products[SettingsStore.nemesisProductID]?.displayPrice
        } catch {
            print("[PurchaseManager] loadProducts error: \(error)")
        }
    }

    func buyRemoveAds() async {
        await buy(SettingsStore.removeAdsProductID)
    }

    func buyNemesis() async {
        await buy(SettingsStore.nemesisProductID)
    }

    private func buy(_ productID: String) async {
        guard let product = products[productID] else {
            errorMessage = "Product not available. Try again later."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    apply(productID: transaction.productID)
                    await transaction.finish()
                }
            case .userCancelled: break
            case .pending: errorMessage = "Purchase pending approval."
            @unknown default: break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result { apply(productID: t.productID) }
        }
    }

    private func apply(productID: String) {
        switch productID {
        case SettingsStore.removeAdsProductID: SettingsStore.shared.markRemoveAdsPurchased()
        case SettingsStore.nemesisProductID:   SettingsStore.shared.markNemesisPurchased()
        default: break
        }
    }
}
