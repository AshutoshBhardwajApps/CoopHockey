import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var products: [Product] = []

    private init() {}

    func loadProducts() async {
        do {
            products = try await Product.products(for: [SettingsStore.removeAdsProductID])
        } catch {
            print("[PurchaseManager] loadProducts error: \(error)")
        }
    }

    func buyRemoveAds() async {
        guard let product = products.first else {
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
                if case .verified = verification {
                    SettingsStore.shared.markRemoveAdsPurchased()
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
        do {
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result,
                   t.productID == SettingsStore.removeAdsProductID {
                    SettingsStore.shared.markRemoveAdsPurchased()
                }
            }
        }
    }
}
