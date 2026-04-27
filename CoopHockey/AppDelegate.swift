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
