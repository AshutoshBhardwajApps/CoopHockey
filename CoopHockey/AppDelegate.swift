import UIKit
import GoogleMobileAds
import AVFAudio
import AppTrackingTransparency
import UserMessagingPlatform

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
        // This hash is derived from the device's advertising identifier, so it
        // changes if that identifier is reset — at which point the device
        // silently starts serving REAL ads to you. Re-read it from the console
        // ("To get test ads on this device, set: ...") whenever that happens.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "c18f2644337b99f078c7f88f6136a82f", // Ashutosh's iPhone (re-read 2026-10-05)
        ]

        // No FBAdSettings.setAdvertiserTrackingEnabled call here on purpose.
        // Audience Network 6.15.0+ on iOS 17+ ignores that flag entirely and
        // reads ATTrackingManager.trackingAuthorizationStatus itself — we ship
        // 6.21.1, so setting it was a deprecated no-op on every device that
        // matters. Dropping it also removes a misleading ordering constraint
        // around MobileAds.start().
        MobileAds.shared.start()

        // For returning users UMP has persisted consent from a previous
        // session, so canRequestAds is already true and we can start
        // preloading in parallel with the ATT/UMP flow below instead of
        // waiting ~5s for them to finish. Single-slot preload wasted 94% of
        // filled ads in production because the next game ended before the
        // next ad arrived; kicking off this early load fills the buffer by
        // the time the first round finishes.
        //
        // First-ever launches fall through to the normal path — UMP's own
        // "no form required" case covers most non-EEA users, so they too
        // get a buffered ad before the second round.
        if ConsentInformation.shared.canRequestAds {
            Task { @MainActor in
                AdManager.shared.preload()
                AdManager.shared.preloadRewarded()
            }
        }

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
            // No [weak self] here: the enclosing asyncAfter block already
            // retains self strongly, so a weak capture would be decorative.
            ConsentManager.shared.gather(from: Self.keyWindowRoot()) {
                self.requestATTThenPreloadAds()
            }
        }
    }

    private func requestATTThenPreloadAds() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
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
