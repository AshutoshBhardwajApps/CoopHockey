import UIKit
import GoogleMobileAds
import AVFAudio
import AppTrackingTransparency

final class AppDelegate: NSObject, UIApplicationDelegate {
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

        MobileAds.shared.start()

        // Request ATT before loading ads so the SDK can serve personalized ads.
        // Preload happens in the callback regardless of the user's choice.
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                Task { @MainActor in AdManager.shared.preload() }
            }
        } else {
            AdManager.shared.preload()
        }

        return true
    }
}
