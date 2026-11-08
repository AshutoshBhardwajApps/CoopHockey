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

    /// When the currently held rewarded ad finished loading. Google expires
    /// rewarded ads after roughly an hour; we discard at 50 minutes so a
    /// player who launched the app and reached the paywall much later isn't
    /// handed a corpse. Presenting a stale ad costs an impression and shows
    /// "no ad ready" for no reason the player can act on.
    private var rewardedLoadedAt: Date?
    private static let rewardedMaxAge: TimeInterval = 50 * 60

    /// Diagnostic counters, persisted so they survive relaunches.
    ///
    /// AdMob cannot distinguish "nobody tapped the button" from "everyone
    /// tapped and the present failed" — both read as requests with zero
    /// impressions. These two numbers separate them, which is the question
    /// that took a month to answer last time.
    private(set) var rewardedPresentAttempts: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.rewAttempts") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.rewAttempts") }
    }
    private(set) var rewardedImpressions: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.rewImpressions") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.rewImpressions") }
    }

    /// Interstitial diagnostics. Same shape as the rewarded counters — same
    /// reason: AdMob reports "requests" and "impressions" per unit but nothing
    /// in between. When fill is high and impressions are zero we need to
    /// separate "the trigger never fired" from "present() was called and
    /// silently did nothing." Persisted so a crash or relaunch does not
    /// erase the only trace of a failure the player will not see.
    private(set) var interstitialPresentAttempts: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.intAttempts") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intAttempts") }
    }
    private(set) var interstitialPresentCalls: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.intCalls") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intCalls") }
    }
    private(set) var interstitialImpressions: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.intImpressions") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intImpressions") }
    }
    private(set) var interstitialPresentFailures: Int {
        get { UserDefaults.standard.integer(forKey: "h.ad.intFailures") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intFailures") }
    }

    /// Reasons `presentIfAllowed` returned early. Encoded as `[rawValue: count]`
    /// in UserDefaults so the diagnostics row can show which gate is firing
    /// most often — the single piece of information that would have made last
    /// month's "zero impressions" investigation take an hour instead of weeks.
    enum InterstitialSkipReason: String {
        case adsDisabled, notActive, pacingRounds, pacingGap,
             noPresenter, alreadyPresenting, noAd
    }
    private var interstitialSkipCounts: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "h.ad.intSkips") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intSkips") }
    }
    private(set) var lastInterstitialSkipReason: String? {
        get { UserDefaults.standard.string(forKey: "h.ad.intLastSkip") }
        set { UserDefaults.standard.set(newValue, forKey: "h.ad.intLastSkip") }
    }

    /// One-line summary for the Settings diagnostics row — readable without
    /// connecting Xcode, so it works for TestFlight builds and players.
    var interstitialDiagnosticsSummary: String {
        let skips = interstitialSkipCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        return """
        Interstitial: \(interstitialPresentAttempts) attempts · \
        \(interstitialPresentCalls) presented · \
        \(interstitialImpressions) impressions · \
        \(interstitialPresentFailures) failures
        Last skip: \(lastInterstitialSkipReason ?? "—")
        Top skips: \(skips.isEmpty ? "—" : skips)
        """
    }

    func resetInterstitialDiagnostics() {
        interstitialPresentAttempts = 0
        interstitialPresentCalls = 0
        interstitialImpressions = 0
        interstitialPresentFailures = 0
        interstitialSkipCounts = [:]
        lastInterstitialSkipReason = nil
    }

    private func noteInterstitialSkip(_ reason: InterstitialSkipReason) {
        var counts = interstitialSkipCounts
        counts[reason.rawValue, default: 0] += 1
        interstitialSkipCounts = counts
        lastInterstitialSkipReason = reason.rawValue
        print("[AdManager] interstitial skip: \(reason.rawValue)")
    }
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
        // The GMA SDK's completion is a @Sendable closure with no main-actor
        // guarantee, so everything that touches this actor's state hops back
        // explicitly. In practice the SDK calls back on main, but that's a
        // convention rather than a contract — and relying on it is a hard
        // error under the Swift 6 language mode.
        InterstitialAd.load(with: interstitialID, request: Request()) { ad, error in
            Task { @MainActor in
                guard !self.adsDisabled else { return }
                if let ad {
                    ad.fullScreenContentDelegate = self
                    self.interstitial = ad
                    print("[AdManager] ✅ loaded")
                } else {
                    print("[AdManager] ❌ load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.preload() }
                }
            }
        }
    }

    // MARK: - Rewarded

    /// Deliberately NOT gated on `adsDisabled`. Remove Ads buys freedom from
    /// *forced* interstitials; a rewarded ad is a trade the player chooses to
    /// make, and cutting it off would leave paying customers unable to earn
    /// NEMESIS games at all.
    func preloadRewarded() {
        discardRewardedIfStale()
        guard rewarded == nil, !rewardedLoading else { return }
        rewardedLoading = true
        RewardedAd.load(with: rewardedID, request: Request()) { ad, error in
            Task { @MainActor in
                self.rewardedLoading = false
                if let ad {
                    ad.fullScreenContentDelegate = self
                    self.rewarded = ad
                    self.rewardedLoadedAt = Date()
                    self.isRewardedReady = true
                    print("[AdManager] ✅ rewarded loaded")
                } else {
                    print("[AdManager] ❌ rewarded load failed: \(error?.localizedDescription ?? "unknown") — retry in 10s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        self.preloadRewarded()
                    }
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
        // Must be the TOPMOST controller, not AdPresenter's fixed anchor. The
        // unlock screen is a fullScreenCover presented over ContentView, so the
        // anchor sits behind it — and UIKit refuses to present from a
        // controller that is already presenting. That silently produced fill
        // with zero impressions on every single rewarded request.
        rewardedPresentAttempts += 1
        discardRewardedIfStale()

        guard let ad = rewarded, let rootVC = Self.topmostPresenterVC() else {
            print("[AdManager] rewarded present skipped — "
                  + "ad=\(rewarded != nil) presenter=\(Self.topmostPresenterVC() != nil)")
            preloadRewarded()
            completion(.unavailable)
            return
        }
        rewarded = nil
        rewardedLoadedAt = nil
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
        interstitialPresentAttempts += 1

        guard !adsDisabled else {
            noteInterstitialSkip(.adsDisabled)
            completion?(false); return
        }
        guard UIApplication.shared.applicationState == .active else {
            noteInterstitialSkip(.notActive)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard roundsSinceLastAd >= minRoundsBetweenAds else {
            noteInterstitialSkip(.pacingRounds)
            completion?(false); return
        }
        if let last = lastShown, Date().timeIntervalSince(last) < minGapSeconds {
            noteInterstitialSkip(.pacingGap)
            completion?(false); return
        }
        guard let rootVC = Self.presenterVC() else {
            noteInterstitialSkip(.noPresenter)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard rootVC.presentedViewController == nil else {
            noteInterstitialSkip(.alreadyPresenting)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentIfAllowed(completion: completion)
            }
            return
        }
        guard let ad = interstitial else {
            noteInterstitialSkip(.noAd)
            preload(); completion?(false); return
        }

        interstitialPresentCalls += 1
        print("[AdManager] interstitial present() called")
        ad.present(from: rootVC)
        lastShown = Date()
        roundsSinceLastAd = 0
        interstitial = nil
        preload()
        completion?(true)
    }

    /// Drops a rewarded ad that has aged past `rewardedMaxAge`, so the next
    /// `preloadRewarded()` fetches a fresh one instead of the guard above
    /// short-circuiting on a stale object.
    private func discardRewardedIfStale() {
        guard rewarded != nil, let at = rewardedLoadedAt,
              Date().timeIntervalSince(at) > Self.rewardedMaxAge else { return }
        print("[AdManager] rewarded aged out after "
              + "\(Int(Date().timeIntervalSince(at) / 60))min — discarding")
        rewarded = nil
        rewardedLoadedAt = nil
        isRewardedReady = false
    }

    // MARK: - Presenter helpers

    /// The controller actually on top of the presentation stack.
    ///
    /// `presenterVC()` deliberately prefers AdPresenter's stable anchor, which
    /// is right for interstitials — they fire at a game break with nothing
    /// covering the game view, and the anchor lets `presentIfAllowed` detect
    /// when a sheet is already up and wait. Anything shown from *inside* a
    /// sheet or cover needs this instead.
    private static func topmostPresenterVC() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let root = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        return topViewController(base: root) ?? AdPresenter.holder
    }

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

    /// The only callback that confirms AdMob actually counted the render.
    /// Without it there is no way to tell a presented-and-counted ad from one
    /// that appeared and silently didn't register.
    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        if presentingRewarded {
            rewardedImpressions += 1
        } else {
            interstitialImpressions += 1
        }
        print("[AdManager] ✅ impression recorded "
              + "(rewarded=\(presentingRewarded))")
    }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        // Loud on purpose. A present failure looks identical to a no-fill in
        // the AdMob report except for match rate, and going unlogged is how
        // 100%-filled rewarded ads served zero impressions unnoticed.
        print("[AdManager] ❌ present failed: \(error.localizedDescription)")

        if !presentingRewarded {
            interstitialPresentFailures += 1
            lastInterstitialSkipReason = "presentFailed: \(error.localizedDescription)"
        }

        if presentingRewarded {
            // The player never saw an ad, so telling them to "finish the ad"
            // would be nonsense. Report it as unavailable and reload.
            presentingRewarded = false
            let done = rewardCompletion
            rewardCompletion = nil
            preloadRewarded()
            done?(.unavailable)
            return
        }
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
