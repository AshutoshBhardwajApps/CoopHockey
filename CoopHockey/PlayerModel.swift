import Foundation

/// A profile of how this human plays, built up shot by shot and persisted
/// across launches so NEMESIS recognises a returning player.
///
/// Everything here is plain arithmetic on a handful of running averages —
/// no ML framework, no network, nothing leaves the device. That is enough to
/// counter habits (banking off the walls, favouring one side, always shooting
/// into the same corner) because those habits are exactly what these few
/// numbers capture.
final class PlayerModel {
    static let shared = PlayerModel()

    /// Weight of a new observation. ~0.18 tracks a change of tactics inside a
    /// single game without one lucky shot swinging the whole profile.
    private let alpha = 0.18

    /// 0 = never banks off a side wall, 1 = every shot is a bank shot.
    private(set) var bankRate: Double
    /// -1 = always attacks up the left wall, +1 = always up the right.
    private(set) var sideBias: Double
    /// Typical shot speed in points/sec. Drives how early NEMESIS commits.
    private(set) var shotSpeed: Double
    /// Share of the player's goals through the left / centre / right third of
    /// the NEMESIS goal mouth. Sums to 1.
    private(set) var goalHeat: [Double]
    /// Completed NEMESIS games, and how many of them the player won.
    private(set) var gamesStudied: Int
    private(set) var playerWins: Int

    /// How hard NEMESIS presses, 0...1, from the player's record against it.
    /// Beating NEMESIS makes it tighten up; it eases off a little when it is
    /// already dominating, so a losing streak doesn't become hopeless.
    var pressure: Double {
        guard gamesStudied >= 2 else { return 0.35 }
        let winRate = Double(playerWins) / Double(gamesStudied)
        return min(1.0, max(0.15, 0.25 + winRate * 1.1))
    }

    /// The third of its own goal NEMESIS has conceded most through, as an x
    /// offset in -1...1. It shades its guard position toward that side.
    var weakSideBias: Double {
        guard let hottest = goalHeat.enumerated().max(by: { $0.element < $1.element })?.offset,
              goalHeat[hottest] > 0.45 else { return 0 }
        return [-1.0, 0.0, 1.0][hottest]
    }

    private init() {
        let d = UserDefaults.standard
        bankRate     = d.object(forKey: "nem.bankRate")  as? Double ?? 0.25
        sideBias     = d.object(forKey: "nem.sideBias")  as? Double ?? 0
        shotSpeed    = d.object(forKey: "nem.shotSpeed") as? Double ?? 520
        goalHeat     = d.object(forKey: "nem.goalHeat")  as? [Double] ?? [1/3, 1/3, 1/3]
        gamesStudied = d.integer(forKey: "nem.games")
        playerWins   = d.integer(forKey: "nem.playerWins")
        if goalHeat.count != 3 { goalHeat = [1/3, 1/3, 1/3] }
    }

    // MARK: - Observations

    /// One completed player shot toward the NEMESIS half.
    /// - Parameters:
    ///   - originX: where the shot was struck, normalised to -1...1.
    ///   - speed: puck speed leaving the mallet, points/sec.
    ///   - banked: whether it touched a side wall before crossing halfway.
    func recordShot(originX: Double, speed: Double, banked: Bool) {
        bankRate  += ((banked ? 1.0 : 0.0) - bankRate) * alpha
        bankRate   = min(1, max(0, bankRate))
        sideBias  += (originX - sideBias) * alpha
        shotSpeed += (speed - shotSpeed) * alpha
        save()
    }

    /// A goal the player scored, by where it crossed the NEMESIS goal line.
    /// - Parameter x: crossing point normalised to -1...1 across the mouth.
    func recordGoalConceded(x: Double) {
        let third = x < -0.33 ? 0 : (x > 0.33 ? 2 : 1)
        for i in 0..<3 {
            goalHeat[i] += ((i == third ? 1 : 0) - goalHeat[i]) * alpha
        }
        let total = goalHeat.reduce(0, +)
        if total > 0 { goalHeat = goalHeat.map { $0 / total } }
        save()
    }

    func recordGameFinished(playerWon: Bool) {
        gamesStudied += 1
        if playerWon { playerWins += 1 }
        save()
    }

    /// Wipe the profile — NEMESIS forgets everything it has learned.
    func reset() {
        bankRate = 0.25
        sideBias = 0
        shotSpeed = 520
        goalHeat = [1/3, 1/3, 1/3]
        gamesStudied = 0
        playerWins = 0
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(bankRate,     forKey: "nem.bankRate")
        d.set(sideBias,     forKey: "nem.sideBias")
        d.set(shotSpeed,    forKey: "nem.shotSpeed")
        d.set(goalHeat,     forKey: "nem.goalHeat")
        d.set(gamesStudied, forKey: "nem.games")
        d.set(playerWins,   forKey: "nem.playerWins")
    }
}
