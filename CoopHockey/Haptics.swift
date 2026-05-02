import UIKit

/// Wrapper around UIFeedbackGenerator for tactile feedback on puck contact,
/// wall bounces, and goals. Always dispatches to the main thread because
/// UIFeedbackGenerator must be invoked there, while SpriteKit's didBegin
/// can fire on the physics thread.
final class Haptics {
    static let shared = Haptics()

    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)
    private let notify       = UINotificationFeedbackGenerator()

    // Coalesce rapid-fire haptics so the engine isn't slammed during fast
    // multi-bounce sequences (which also feels less satisfying).
    private var lastFireTime: TimeInterval = 0
    private let cooldown: TimeInterval = 0.045

    private init() {
        DispatchQueue.main.async { [self] in
            lightImpact.prepare()
            mediumImpact.prepare()
            heavyImpact.prepare()
            notify.prepare()
        }
    }

    // MARK: - Public

    /// Mallet ↔ puck contact. `intensity` 0…1 (typically derived from approach speed).
    func puckHit(intensity: CGFloat) {
        guard SettingsStore.shared.effectsEnabled else { return }
        guard cooldownPassed() else { return }
        let i = max(0.25, min(1.0, intensity))
        DispatchQueue.main.async { [self] in
            if i > 0.7 {
                mediumImpact.impactOccurred(intensity: i)
                mediumImpact.prepare()
            } else {
                lightImpact.impactOccurred(intensity: i)
                lightImpact.prepare()
            }
        }
    }

    /// Puck ↔ wall bounce. Softer than a mallet hit.
    func wallBounce(intensity: CGFloat) {
        guard SettingsStore.shared.effectsEnabled else { return }
        guard cooldownPassed() else { return }
        let i = max(0.15, min(0.7, intensity))
        DispatchQueue.main.async { [self] in
            lightImpact.impactOccurred(intensity: i)
            lightImpact.prepare()
        }
    }

    /// Goal scored — celebratory thump + success notification.
    func goal() {
        guard SettingsStore.shared.effectsEnabled else { return }
        DispatchQueue.main.async { [self] in
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
            notify.notificationOccurred(.success)
            notify.prepare()
        }
    }

    private func cooldownPassed() -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastFireTime >= cooldown else { return false }
        lastFireTime = now
        return true
    }
}
