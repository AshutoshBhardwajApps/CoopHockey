import Foundation
import GoogleMobileAds
import UIKit

extension Notification.Name {
    static let adWillPresent = Notification.Name("AdManager.adWillPresent")
    static let adDidDismiss  = Notification.Name("AdManager.adDidDismiss")
}

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // REPLACE with your real interstitial unit ID from console.admob.com
    // Using Google's demo test ID below so test ads work immediately.
    // Real ID format: "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"
    private let interstitialID = "ca-app-pub-2320635595451132/7068208518"

    private let minRoundsBetweenAds: Int = 1
    private let minGapSeconds: TimeInterval = 0

    private var lastShown: Date?
    private var roundsSinceLastAd = 0
    private var interstitial: InterstitialAd?

    private override init() { super.init() }

    private var adsDisabled: Bool { SettingsStore.shared.hasRemovedAds }

    // MARK: - Preload

    func preload() {
        guard !adsDisabled else { interstitial = nil; return }
        InterstitialAd.load(with: interstitialID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            guard !self.adsDisabled else { return }
            if let ad {
                ad.fullScreenContentDelegate = self
                self.interstitial = ad
                print("[AdManager] ✅ loaded")
            } else {
                print("[AdManager] ❌ load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.preload() }
            }
        }
    }

    // MARK: - Round tracking

    func noteRoundCompleted() {
        guard !adsDisabled else { return }
        roundsSinceLastAd += 1
    }

    // MARK: - Present

    func presentIfAllowed(completion: ((Bool) -> Void)? = nil) {
        guard !adsDisabled else { completion?(false); return }
        guard UIApplication.shared.applicationState == .active else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard roundsSinceLastAd >= minRoundsBetweenAds else { completion?(false); return }
        if let last = lastShown, Date().timeIntervalSince(last) < minGapSeconds {
            completion?(false); return
        }
        guard let rootVC = Self.presenterVC() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard rootVC.presentedViewController == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard let ad = interstitial else { preload(); completion?(false); return }

        ad.present(from: rootVC)
        lastShown = Date()
        roundsSinceLastAd = 0
        interstitial = nil
        preload()
        completion?(true)
    }

    // MARK: - Presenter helpers

    private static func presenterVC() -> UIViewController? {
        if let vc = AdPresenter.holder, vc.viewIfLoaded?.window != nil { return vc }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let root = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        return topViewController(base: root)
    }

    private static func topViewController(base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController, let sel = tab.selectedViewController { return topViewController(base: sel) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}

// MARK: - Delegate

extension AdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        NotificationCenter.default.post(name: .adWillPresent, object: nil)
    }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }
}
