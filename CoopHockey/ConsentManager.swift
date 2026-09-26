import Foundation
import UIKit
import UserMessagingPlatform

/// Wraps Google's User Messaging Platform — the Google-certified CMP that
/// gathers GDPR/TCF consent for users in the EEA, the UK and Switzerland.
///
/// The UMP package was linked to this project long before any of it was
/// called, which meant EEA players could only ever be served non-personalised
/// ads (capping eCPM there) and Ad Inspector showed blank consent signals.
///
/// Outside those regions UMP answers "no form required" and the whole thing
/// falls through in a single network round trip, so US traffic — which is
/// most of the player base — pays almost nothing for this.
///
/// Deliberately *not* `@MainActor`: `AppDelegate` isn't either, and UMP
/// already delivers its callbacks on the main thread.
final class ConsentManager {

    static let shared = ConsentManager()
    private init() {}

    #if DEBUG
    /// Flip to true to make UMP behave as though the device is in the EEA, so
    /// the consent form actually appears during development. Left off by
    /// default — otherwise the form interrupts every single debug launch.
    ///
    /// Pair it with `reset()` from the Settings DEBUG section; UMP remembers
    /// the answer and won't re-present the form until consent is cleared.
    static let forceEEAForTesting = false
    #endif

    /// UMP's own verdict on whether ads may be requested at all. True outside
    /// the EEA, and true inside it once the form has been answered.
    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }

    /// Refreshes consent state and presents the form only if UMP says one is
    /// required.
    ///
    /// `completion` runs exactly once, on the main thread, whether or not
    /// anything failed. A consent error must never leave the app without ads
    /// — Google's guidance is to fall back to non-personalised serving, which
    /// is what the SDK does on its own when consent is absent.
    func gather(from viewController: UIViewController?,
                completion: @escaping () -> Void) {

        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        #if DEBUG
        if Self.forceEEAForTesting {
            let debug = DebugSettings()
            debug.geography = .EEA
            debug.testDeviceIdentifiers = ["979fc0c499c82c5211db23733cdf821d"]
            parameters.debugSettings = debug
        }
        #endif

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            if let error {
                print("[Consent] info update failed: \(error.localizedDescription)")
                Self.finish(completion)
                return
            }

            guard let viewController else {
                print("[Consent] no presenter available; skipping form")
                Self.finish(completion)
                return
            }

            ConsentForm.loadAndPresentIfRequired(from: viewController) { formError in
                if let formError {
                    print("[Consent] form failed: \(formError.localizedDescription)")
                }
                print("[Consent] canRequestAds=\(self?.canRequestAds ?? false)")
                Self.finish(completion)
            }
        }
    }

    private static func finish(_ completion: @escaping () -> Void) {
        if Thread.isMainThread {
            completion()
        } else {
            DispatchQueue.main.async(execute: completion)
        }
    }

    #if DEBUG
    /// Clears stored consent so the form presents again on the next launch.
    func reset() {
        ConsentInformation.shared.reset()
        print("[Consent] reset — form will show again next launch")
    }
    #endif
}
