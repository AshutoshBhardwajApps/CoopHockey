import SwiftUI

/// Store page for the NEMESIS difficulty. Sells the mode on what actually
/// makes it different — it reads bank shots, guards its net instead of
/// mirroring you, and carries what it learned into the next game.
struct NemesisUnlockView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    /// True when shown because the free trial just ran out, rather than from
    /// the menu. Changes the framing from "here's what it is" to "here's what
    /// you've been playing".
    var trialEnded: Bool = false
    let onDismiss: () -> Void

    @State private var purchasing = false

    private var studied: Int { PlayerModel.shared.gamesStudied }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.03, blue: 0.10),
                    Color(red: 0.03, green: 0.02, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundColor(Theme.nemesisColor)
                    .shadow(color: Theme.nemesisColor.opacity(0.7), radius: 20)

                VStack(spacing: 8) {
                    Text(trialEnded ? "FREE TRIAL OVER" : "NEW DIFFICULTY")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(3)
                    Text("NEMESIS")
                        .font(.system(size: 42, weight: .black))
                        .foregroundColor(.white)
                        .tracking(2)
                    if trialEnded {
                        Text("Keep the opponent that has been learning you.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "arrow.turn.up.right",
                               title: "Reads your bank shots",
                               detail: "Tracks the puck through wall bounces instead of guessing a straight line.")
                    FeatureRow(icon: "shield.lefthalf.filled",
                               title: "Guards the net",
                               detail: "Holds a goalie line between you and its goal — it no longer just mirrors your mallet.")
                    FeatureRow(icon: "brain.head.profile",
                               title: "Learns and remembers",
                               detail: "Studies your favourite side and scoring corner, and presses harder every time you win.")
                }
                .padding(.horizontal, 30)

                if studied > 0 {
                    Text("It has already studied \(studied) of your games.")
                        .font(.caption)
                        .foregroundColor(Theme.nemesisColor.opacity(0.9))
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        purchasing = true
                        Task {
                            await purchaseManager.buyNemesis()
                            purchasing = false
                            if settings.hasNemesis { onDismiss() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if purchasing || purchaseManager.isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text("UNLOCK NEMESIS")
                                if let price = purchaseManager.nemesisPrice {
                                    Text("· \(price)").foregroundColor(.black.opacity(0.65))
                                }
                            }
                        }
                        .font(.system(size: 19, weight: .black))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Theme.nemesisColor)
                        .cornerRadius(16)
                    }
                    .disabled(purchasing || purchaseManager.isLoading)

                    Button("Restore Purchases") {
                        Task { await purchaseManager.restorePurchases() }
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))

                    Button(trialEnded ? "Back to menu" : "Not now") { onDismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 34)

                if let msg = purchaseManager.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer(minLength: 12)
            }
        }
        .task { await purchaseManager.loadProducts() }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.nemesisColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
