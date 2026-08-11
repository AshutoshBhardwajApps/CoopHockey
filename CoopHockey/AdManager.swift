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

    // Real production interstitial unit ID.
    // For development: register your device as a test device (see start() below)
    // and AdMob will serve test ads on it even with this real ID.
    private let interstitialID = "ca-app-pub-2320635595451132/7068208518"

    private let minRoundsBetweenAds: Int = 1
    private let minGapSeconds: TimeInterval = 0

    /// Guarantee a Remove Ads promo every Nth completed game, bypassing the
    /// random odds and ad-pacing gates. Random promo rolls still happen on
    /// other games — this is a floor, not a ceiling.
    private let forcePromoEvery: Int = 8

    /// Rewarded unit — one view grants one NEMESIS game.
    ///
    /// Debug builds use Google's always-filling rewarded test unit. A newly
    /// created AdMob unit answers "No ad to show" for hours, which blocks
    /// testing the earn-a-game flow entirely. Release always uses the real
    /// unit, so shipping behaviour is unaffected.
    #if DEBUG
    private let rewardedID = "ca-app-pub-3940256099942544/1712485313"
    #else
    private let rewardedID = "ca-app-pub-2320635595451132/2857049425"
    #endif

    private var lastShown: Date?
    private var roundsSinceLastAd = 0
    private var gamesSincePromo = 0
    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var rewardedLoading = false
    private var presentingRewarded = false
    private var rewardEarned = false
    private var rewardCompletion: ((RewardOutcome) -> Void)?

    /// Why a rewarded attempt ended. "No ad to show" and "you closed it early"
    /// are completely different situations and must not share a message —
    /// telling someone to finish an ad they were never shown is nonsense.
    enum RewardOutcome {
        case earned
        case dismissedEarly
        case unavailable
    }

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

    // MARK: - Rewarded

    /// Deliberately NOT gated on `adsDisabled`. Remove Ads buys freedom from
    /// *forced* interstitials; a rewarded ad is a trade the player chooses to
    /// make, and cutting it off would leave paying customers unable to earn
    /// NEMESIS games at all.
    func preloadRewarded() {
        guard rewarded == nil, !rewardedLoading else { return }
        rewardedLoading = true
        RewardedAd.load(with: rewardedID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            self.rewardedLoading = false
            if let ad {
                ad.fullScreenContentDelegate = self
                self.rewarded = ad
                self.isRewardedReady = true
                print("[AdManager] ✅ rewarded loaded")
            } else {
                print("[AdManager] ❌ rewarded load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.preloadRewarded()
                }
            }
        }
    }

    /// Published so the unlock screen can show a "preparing" state instead of
    /// letting the player tap into a failure while the video is still loading.
    @Published private(set) var isRewardedReady = false

    /// Shows the rewarded ad. `completion(true)` only if the reward was
    /// actually earned — dismissing early must not grant a free game.
    func presentRewarded(completion: @escaping (RewardOutcome) -> Void) {
        guard let ad = rewarded, let rootVC = Self.presenterVC() else {
            preloadRewarded()
            completion(.unavailable)
            return
        }
        rewarded = nil
        isRewardedReady = false
        rewardEarned = false
        presentingRewarded = true
        rewardCompletion = completion
        ad.present(from: rootVC) { [weak self] in
            self?.rewardEarned = true
        }
        preloadRewarded()   // have the next one ready
    }

    // MARK: - Round tracking

    func noteRoundCompleted() {
        guard !adsDisabled else { return }
        roundsSinceLastAd += 1
        gamesSincePromo += 1
    }

    /// Whether to show the Remove Ads promo in place of an interstitial.
    /// Two paths:
    ///   1. Forced: guaranteed promo every Nth completed game, bypassing the
    ///      ad-pacing gates so it always lands.
    ///   2. Random: ~1-in-12 chance on other game-end slots, still gated by
    ///      the normal ad pacing (rounds-between, gap, ads-not-disabled).
    func shouldShowPromoInsteadOfAd() -> Bool {
        guard !adsDisabled else { return false }
        if gamesSincePromo >= forcePromoEvery { return true }
        guard roundsSinceLastAd >= minRoundsBetweenAds else { return false }
        if let last = lastShown, Date().timeIntervalSince(last) < minGapSeconds { return false }
        return Int.random(in: 0..<12) == 0
    }

    /// Mark a promo as having "consumed" the current ad slot — resets the
    /// round counter and timestamp the same way a real ad show would.
    func notePromoShown() {
        roundsSinceLastAd = 0
        gamesSincePromo = 0
        lastShown = Date()
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
        if finishRewardedIfNeeded() { return }
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        if finishRewardedIfNeeded() { return }
        NotificationCenter.default.post(name: .adDidDismiss, object: nil)
    }

    /// Rewarded ads settle through their own completion rather than the
    /// interstitial notifications, which drive the post-game result sheet.
    private func finishRewardedIfNeeded() -> Bool {
        guard presentingRewarded else { return false }
        presentingRewarded = false
        let earned = rewardEarned
        let done = rewardCompletion
        rewardCompletion = nil
        done?(earned ? .earned : .dismissedEarly)
        return true
    }
}
