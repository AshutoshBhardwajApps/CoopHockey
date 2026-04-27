import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let removeAdsProductID = "coophockey.removeads"
    static let targetScoreOptions  = [5, 7, 9]

    @Published var player1Name: String   { didSet { save() } }
    @Published var player2Name: String   { didSet { save() } }
    @Published var targetScore: Int      { didSet { save() } }
    @Published var musicEnabled: Bool    { didSet { save() } }
    @Published var effectsEnabled: Bool  { didSet { save() } }
    @Published var hasRemovedAds: Bool   { didSet { save() } }

    @Published private(set) var totalGamesPlayed: Int
    @Published private(set) var p1WinsTotal: Int
    @Published private(set) var p2WinsTotal: Int

    var totalWins: Int { p1WinsTotal + p2WinsTotal }

    private init() {
        let d = UserDefaults.standard
        player1Name      = d.string(forKey: "h.p1.name")             ?? "PLAYER 1"
        player2Name      = d.string(forKey: "h.p2.name")             ?? "PLAYER 2"
        targetScore      = d.object(forKey: "h.targetScore") as? Int ?? 7
        musicEnabled     = d.object(forKey: "h.music")    as? Bool   ?? true
        effectsEnabled   = d.object(forKey: "h.effects")  as? Bool   ?? true
        hasRemovedAds    = d.bool(forKey: "h.removeAds")
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

    private func save() {
        let d = UserDefaults.standard
        d.set(player1Name,      forKey: "h.p1.name")
        d.set(player2Name,      forKey: "h.p2.name")
        d.set(targetScore,      forKey: "h.targetScore")
        d.set(musicEnabled,     forKey: "h.music")
        d.set(effectsEnabled,   forKey: "h.effects")
        d.set(hasRemovedAds,    forKey: "h.removeAds")
        d.set(totalGamesPlayed, forKey: "h.gamesPlayed")
        d.set(p1WinsTotal,      forKey: "h.p1Wins")
        d.set(p2WinsTotal,      forKey: "h.p2Wins")
    }
}
