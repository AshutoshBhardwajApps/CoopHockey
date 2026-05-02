import SwiftUI

/// Full-screen promo that appears in place of a real interstitial ~1-in-5
/// game-over slots. Lets the user buy the Remove Ads IAP without digging
/// into Settings — and gives a no-pressure "Continue" out so the flow back
/// to the result sheet is one tap.
struct RemoveAdsPromoView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    /// Called whenever the user dismisses the promo (continue, close, or
    /// successful purchase). Caller is responsible for advancing the flow
    /// (typically: hide promo, then show the result sheet).
    let onDismiss: () -> Void

    @State private var purchasing = false

    var body: some View {
        ZStack {
            // Same dark backdrop as the result sheet so the transition feels
            // intentional rather than jarring.
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.10, blue: 0.20),
                    Color(red: 0.02, green: 0.04, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.cyan)
                    .shadow(color: .cyan.opacity(0.6), radius: 18)

                VStack(spacing: 10) {
                    Text("ENJOYING")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(3)
                    Text("COOP AIRHOCKEY?")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    Text("Skip the ads forever.")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))

                    Text("One-time purchase. Supports the developer.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: buy) {
                        HStack(spacing: 10) {
                            if purchasing {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "nosign")
                                Text(buyButtonTitle)
                            }
                        }
                        .font(.system(size: 19, weight: .black))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.cyan)
                        .cornerRadius(16)
                    }
                    .disabled(purchasing)

                    Button(action: onDismiss) {
                        Text("Continue with ads")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.vertical, 10)
                    }

                    if let msg = purchaseManager.errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }

            // Small close button in the corner — same convention as the
            // game's pause/exit buttons so it feels familiar.
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
        .task { await purchaseManager.loadProducts() }
        .onChange(of: settings.hasRemovedAds) { hasRemoved in
            // Successful purchase auto-dismisses so the user lands back in
            // the result flow with no extra taps.
            if hasRemoved { onDismiss() }
        }
    }

    private var buyButtonTitle: String {
        if let price = purchaseManager.localizedPrice {
            return "Remove Ads — \(price)"
        }
        return "Remove Ads"
    }

    private func buy() {
        purchasing = true
        Task {
            await purchaseManager.buyRemoveAds()
            purchasing = false
        }
    }
}
