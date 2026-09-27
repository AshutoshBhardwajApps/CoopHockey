import SwiftUI

@main
struct CoopHockeyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings      = SettingsStore.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var scores        = HighScoresStore.shared
    @StateObject private var gameCenter    = GameCenterManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .environmentObject(purchaseManager)
                .environmentObject(scores)
                .environmentObject(gameCenter)
                .preferredColorScheme(.dark)
                .task {
                    // Game Center may present its own sign-in sheet, so this
                    // runs from .task rather than the AppDelegate — there is
                    // a window to present from by the time the view appears.
                    gameCenter.authenticate()
                    await purchaseManager.loadProducts()
                    await purchaseManager.restorePurchases()
                }
        }
    }
}
