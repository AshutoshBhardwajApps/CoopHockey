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

    /// Legacy key from the 15-minute timed trial, read once at launch to
    /// decide whether an upgrading player has already had their free taste.
    private static let legacyTrialKey   = "h.nemesisTrial"
    private static let legacyTrialLimit: TimeInterval = 15 * 60

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

    // Deliberately no `totalWins`: every game has a winner, so the sum of the
    // two counters is just the number of games played. Displaying it beside
    // "Games" made the two figures identical and looked like a bug.

    /// One free NEMESIS game, once per install, so a player knows what the
    /// unlock actually buys before paying for it. Replaced the 15-minute
    /// timed trial: the timer had to tick every frame during play, and at
    /// roughly one game per session nobody ever reached the end of it anyway.
    @Published private(set) var hasUsedFreeNemesisGame: Bool

    /// How the player is getting into a NEMESIS game right now.
    enum NemesisAccess { case owned, freeGame, credit, locked }

    var nemesisAccess: NemesisAccess {
        if hasNemesis { return .owned }
        if !hasUsedFreeNemesisGame { return .freeGame }
        if nemesisGameCredits > 0 { return .credit }
        return .locked
    }
    var canPlayNemesis: Bool { nemesisAccess != .locked }

    /// Games earned by watching rewarded ads. One ad, one game — spent when
    /// a game actually begins.
    @Published private(set) var nemesisGameCredits: Int

    func grantNemesisGame() {
        nemesisGameCredits += 1
        save()
    }

    func spendNemesisGame() {
        guard nemesisGameCredits > 0 else { return }
        nemesisGameCredits -= 1
        save()
    }

    /// Burns the one-off free game. Called when a NEMESIS game actually
    /// starts, not when the player merely looks at the screen.
    func consumeFreeNemesisGame() {
        guard !hasUsedFreeNemesisGame else { return }
        hasUsedFreeNemesisGame = true
        save()
    }

    #if DEBUG
    /// Jump straight to the paywall without spending the free game.
    func expireNemesisTrial() {
        hasUsedFreeNemesisGame = true
        save()
    }

    func resetNemesisTrial() {
        hasUsedFreeNemesisGame = false
        nemesisGameCredits = 0
        save()
    }
    #endif

    private init() {
        let d = UserDefaults.standard
        player1Name      = d.string(forKey: "h.p1.name")             ?? "PLAYER 1"
        player2Name      = d.string(forKey: "h.p2.name")             ?? "PLAYER 2"
        targetScore      = d.object(forKey: "h.targetScore") as? Int ?? 7
        musicEnabled     = d.object(forKey: "h.music")    as? Bool   ?? true
        effectsEnabled   = d.object(forKey: "h.effects")  as? Bool   ?? true
        hasRemovedAds    = d.bool(forKey: "h.removeAds")
        hasNemesis       = d.bool(forKey: "h.nemesis")
        nemesisGameCredits = d.integer(forKey: "h.nemesisCredits")

        // Migration off the timed trial. A player who burned all 15 minutes
        // has already had their taste, so they don't also get a free game;
        // anyone mid-trial keeps one. Once the flag has been written the
        // legacy key is never consulted again.
        if d.object(forKey: "h.nemesisFreeUsed") != nil {
            hasUsedFreeNemesisGame = d.bool(forKey: "h.nemesisFreeUsed")
        } else {
            hasUsedFreeNemesisGame =
                d.double(forKey: Self.legacyTrialKey) >= Self.legacyTrialLimit
        }
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
        d.set(hasUsedFreeNemesisGame, forKey: "h.nemesisFreeUsed")
        d.set(nemesisGameCredits, forKey: "h.nemesisCredits")
        d.set(totalGamesPlayed, forKey: "h.gamesPlayed")
        d.set(p1WinsTotal,      forKey: "h.p1Wins")
        d.set(p2WinsTotal,      forKey: "h.p2Wins")
    }
}
