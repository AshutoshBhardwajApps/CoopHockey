import Foundation
import GameKit
import SwiftUI

/// Game Center: authentication and leaderboard submission.
///
/// Scope is deliberately narrow — leaderboards only, no achievements and no
/// matchmaking. Authentication is best-effort: a player who declines Game
/// Center, or has no network, must lose nothing. Every submission path is a
/// no-op when unauthenticated rather than an error the player has to see.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {

    static let shared = GameCenterManager()
    private override init() { super.init() }

    /// Leaderboard IDs. These must match the records created in App Store
    /// Connect letter-for-letter, or submissions fail silently.
    enum Leaderboard: String, CaseIterable {
        case totalWins    = "coophockey.leaderboard.totalwins"
        case nemesisWins  = "coophockey.leaderboard.nemesiswins"
        case bestWinScore = "coophockey.leaderboard.bestwinscore"
    }

    @Published private(set) var isAuthenticated = false

    /// Local mirrors of the submitted totals. Game Center has no "increment"
    /// operation — every submission replaces the stored value — so the app
    /// has to keep its own running count and submit the new total.
    private var totalWins: Int {
        get { UserDefaults.standard.integer(forKey: "h.gc.totalWins") }
        set { UserDefaults.standard.set(newValue, forKey: "h.gc.totalWins") }
    }
    private var nemesisWins: Int {
        get { UserDefaults.standard.integer(forKey: "h.gc.nemesisWins") }
        set { UserDefaults.standard.set(newValue, forKey: "h.gc.nemesisWins") }
    }

    // MARK: - Authentication

    /// Call once at launch. GameKit presents its own sign-in sheet if needed,
    /// so this must run after there is a window to present from.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }

                if let viewController {
                    // GameKit wants to show its sign-in UI. Present from the
                    // topmost controller — the plain root may be covered by a
                    // game or a sheet, and UIKit refuses to present from a
                    // controller that is already presenting.
                    Self.topmostViewController()?.present(viewController,
                                                          animated: true)
                    return
                }

                if let error {
                    print("[GameCenter] auth failed: \(error.localizedDescription)")
                    self.isAuthenticated = false
                    return
                }

                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                print("[GameCenter] authenticated=\(self.isAuthenticated)")
                if self.isAuthenticated { self.submitPendingTotals() }
            }
        }
    }

    // MARK: - Submission

    /// Records a finished game. `playerWon` refers to Player 1 — the local
    /// player's side in every single-device mode.
    func recordGameFinished(playerWon: Bool,
                            wasNemesis: Bool,
                            winningScore: Int,
                            losingScore: Int) {
        guard playerWon else { return }

        totalWins += 1
        if wasNemesis { nemesisWins += 1 }

        submit(totalWins, to: .totalWins)
        if wasNemesis { submit(nemesisWins, to: .nemesisWins) }

        // Margin of victory, so a 7–0 shutout outranks a 7–6 scrape. Best
        // score wins on this board, so submitting a worse one is harmless —
        // Game Center keeps the player's best automatically.
        submit(winningScore - losingScore, to: .bestWinScore)
    }

    /// Re-submits current totals, for the case where earlier games finished
    /// while the player was signed out.
    private func submitPendingTotals() {
        if totalWins   > 0 { submit(totalWins,   to: .totalWins) }
        if nemesisWins > 0 { submit(nemesisWins, to: .nemesisWins) }
    }

    private func submit(_ value: Int, to leaderboard: Leaderboard) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(
            value,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboard.rawValue]
        ) { error in
            if let error {
                print("[GameCenter] submit to \(leaderboard.rawValue) failed: "
                      + error.localizedDescription)
            }
        }
    }

    // MARK: - Presentation

    /// Opens Game Center's own leaderboard dashboard.
    func showLeaderboards() {
        guard isAuthenticated, let presenter = Self.topmostViewController() else { return }
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        presenter.present(vc, animated: true)
    }

    private static func topmostViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Dashboard dismissal

extension GameCenterManager: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(
        _ gameCenterViewController: GKGameCenterViewController
    ) {
        Task { @MainActor in
            gameCenterViewController.dismiss(animated: true)
        }
    }
}
