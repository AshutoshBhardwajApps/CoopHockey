import UIKit
import GoogleMobileAds
import AVFAudio
import AppTrackingTransparency
import FBAudienceNetwork

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// One-shot guard so we only request ATT once per launch even if
    /// didBecomeActive fires multiple times (e.g. user toggled Control
    /// Center, returned to app, etc.).
    private var attRequested = false
    private var didBecomeActiveObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true, options: [])
        } catch {
            print("Audio session error: \(error)")
        }

        // Register test devices so real ad-unit IDs serve TEST ads on these devices.
        // Find your device's hashed ID in the Xcode console after the first ad request:
        //   "To get test ads on this device, set: Mobile Ads SDK ... testDeviceIdentifiers = @[ @"ABC123..." ]"
        // Paste that hash into the array below. Safe to ship with real device IDs in production —
        // it only affects the listed devices.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "979fc0c499c82c5211db23733cdf821d", // Ashutosh's iPhone
        ]

        // Meta Audience Network (mediation bidding) needs its Advertiser
        // Tracking Enabled flag set before the Google Mobile Ads SDK
        // initializes its adapters. On first launch ATT is .notDetermined so
        // this starts false; requestATTIfNeeded() updates it once the user
        // answers the prompt (subsequent launches pick up the stored status).
        if #available(iOS 14, *) {
            FBAdSettings.setAdvertiserTrackingEnabled(
                ATTrackingManager.trackingAuthorizationStatus == .authorized
            )
        }

        MobileAds.shared.start()

        // ATT must be requested when the app is in the .active state. Calling
        // it from didFinishLaunching is too early — iOS silently no-ops the
        // request and the dialog never shows (this is exactly what App Store
        // review flagged in the 1.3(14) rejection). Defer to didBecomeActive
        // and add a small delay so the launch transition completes before the
        // system alert tries to present.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestATTIfNeeded()
        }

        return true
    }

    private func requestATTIfNeeded() {
        guard !attRequested else { return }
        attRequested = true

        // Stop listening — one-shot.
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }

        // 0.4s delay lets the launch transition finish; without it the alert
        // can race with the first frame and either be dropped or appear
        // before the app's UI is visible (which Apple also dislikes).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // UMP consent runs BEFORE ATT. In the EEA/UK/Switzerland a
            // Google-certified CMP has to gather GDPR consent or those users
            // can only ever be served non-personalised ads. Everywhere else
            // UMP reports "no form required" and this falls straight through.
            //
            // Ads are only preloaded once both prompts have been answered, so
            // the first request carries the right consent and ATT signals.
            ConsentManager.shared.gather(from: Self.keyWindowRoot()) { [weak self] in
                self?.requestATTThenPreloadAds()
            }
        }
    }

    private func requestATTThenPreloadAds() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                FBAdSettings.setAdvertiserTrackingEnabled(status == .authorized)
                Task { @MainActor in
                    AdManager.shared.preload()
                    // Warm the rewarded ad at launch too. Loading it only
                    // when the unlock screen appears means a quick tap
                    // finds nothing ready.
                    AdManager.shared.preloadRewarded()
                }
            }
        } else {
            Task { @MainActor in AdManager.shared.preload() }
        }
    }

    /// Root controller of the active scene's key window — where the UMP
    /// consent form presents from. Nothing is covering the UI this early in
    /// launch, so the plain root is the right anchor here.
    private static func keyWindowRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
    }
}
