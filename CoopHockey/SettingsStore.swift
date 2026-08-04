import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // v2 of the Remove Ads product. The original `coophockey.removeads`
    // got stuck in App Store Connect after the 1.3(14) rejection chain;
    // creating a fresh ID lets us re-link the IAP to the build cleanly.
    static let removeAdsProductID = "coophockey.removeads2"
    static let nemesisProductID   = "coophockey.nemesis"
    static let targetScoreOptions  = [5, 7, 9]

    /// Free NEMESIS play before the unlock is required. Only live play counts
    /// — menus, pauses and result screens don't burn the trial.
    static let nemesisTrialLimit: TimeInterval = 15 * 60

    @Published var player1Name: String   { didSet { save() } }
    @Published var player2Name: String   { didSet { save() } }
    @Published var targetScore: Int      { didSet { save() } }
    @Published var musicEnabled: Bool    { didSet { save() } }
    @Published var effectsEnabled: Bool  { didSet { save() } }
    @Published var hasRemovedAds: Bool   { didSet { save() } }
    @Published var hasNemesis: Bool      { didSet { save() } }

    @Published private(set) var totalGamesPlayed: Int
    @Published private(set) var p1WinsTotal: Int
    @Published private(set) var p2WinsTotal: Int

    var totalWins: Int { p1WinsTotal + p2WinsTotal }

    /// Trial seconds already spent. Deliberately *not* @Published: it ticks
    /// once a second during play, and republishing would re-render the live
    /// game view for nothing. Screens that display it read it on appear.
    private(set) var nemesisTrialUsed: TimeInterval
    private var trialUnsaved: TimeInterval = 0

    var nemesisTrialRemaining: TimeInterval {
        max(0, Self.nemesisTrialLimit - nemesisTrialUsed)
    }
    var nemesisTrialExpired: Bool { nemesisTrialRemaining <= 0 }
    var canPlayNemesis: Bool { hasNemesis || !nemesisTrialExpired }

    func addNemesisTrialTime(_ seconds: TimeInterval) {
        guard !hasNemesis else { return }
        nemesisTrialUsed += seconds
        trialUnsaved += seconds
        // Persist every ~5s instead of every tick; also flushed when play
        // stops. Erring toward under-counting is the player-friendly bug.
        if trialUnsaved >= 5 { flushNemesisTrial() }
    }

    #if DEBUG
    /// Playtesting helper — hand the 15 minutes back.
    func resetNemesisTrial() {
        nemesisTrialUsed = 0
        trialUnsaved = 0
        UserDefaults.standard.set(0.0, forKey: "h.nemesisTrial")
    }
    #endif

    func flushNemesisTrial() {
        guard trialUnsaved > 0 else { return }
        trialUnsaved = 0
        UserDefaults.standard.set(nemesisTrialUsed, forKey: "h.nemesisTrial")
    }

    private init() {
        let d = UserDefaults.standard
        player1Name      = d.string(forKey: "h.p1.name")             ?? "PLAYER 1"
        player2Name      = d.string(forKey: "h.p2.name")             ?? "PLAYER 2"
        targetScore      = d.object(forKey: "h.targetScore") as? Int ?? 7
        musicEnabled     = d.object(forKey: "h.music")    as? Bool   ?? true
        effectsEnabled   = d.object(forKey: "h.effects")  as? Bool   ?? true
        hasRemovedAds    = d.bool(forKey: "h.removeAds")
        hasNemesis       = d.bool(forKey: "h.nemesis")
        nemesisTrialUsed = d.double(forKey: "h.nemesisTrial")
        totalGamesPlayed = d.integer(forKey: "h.gamesPlayed")
        p1WinsTotal      = d.integer(forKey: "h.p1Wins")
        p2WinsTotal      = d.integer(forKey: "h.p2Wins")
    }

    func registerResult(winner: Int?) {
        totalGamesPlayed += 1
        if winner == 1 { p1WinsTotal += 1 }
        if winner == 2 { p2WinsTotal += 1 }
        save()
    }

    func markRemoveAdsPurchased() { hasRemovedAds = true }
    func markNemesisPurchased()   { hasNemesis = true }

    private func save() {
        let d = UserDefaults.standard
        d.set(player1Name,      forKey: "h.p1.name")
        d.set(player2Name,      forKey: "h.p2.name")
        d.set(targetScore,      forKey: "h.targetScore")
        d.set(musicEnabled,     forKey: "h.music")
        d.set(effectsEnabled,   forKey: "h.effects")
        d.set(hasRemovedAds,    forKey: "h.removeAds")
        d.set(hasNemesis,       forKey: "h.nemesis")
        d.set(nemesisTrialUsed, forKey: "h.nemesisTrial")
        d.set(totalGamesPlayed, forKey: "h.gamesPlayed")
        d.set(p1WinsTotal,      forKey: "h.p1Wins")
        d.set(p2WinsTotal,      forKey: "h.p2Wins")
    }
}
