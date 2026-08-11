import Foundation
import Combine

enum AIDifficulty: String, CaseIterable, Equatable {
    case easy    = "EASY"
    case medium  = "MEDIUM"
    case hard    = "HARD"
    case nemesis = "NEMESIS"

    /// Difficulties sold as an in-app purchase rather than shipped unlocked.
    var isPremium: Bool { self == .nemesis }

    /// The free ladder, in order. NEMESIS is deliberately excluded so the
    /// home screen can present it separately as a locked tier.
    static var freeCases: [AIDifficulty] { [.easy, .medium, .hard] }
}

enum GameMode: Equatable, Identifiable {
    case twoPlayer
    case vsComputer(AIDifficulty)

    var id: String {
        switch self {
        case .twoPlayer:          return "twoPlayer"
        case .vsComputer(let d):  return "vsComputer-\(d.rawValue)"
        }
    }
}

enum GameState: Equatable {
    case idle
    case playing
    case goalScored(by: Int)
    case gameOver(winner: Int)
}

final class GameCoordinator: ObservableObject {

    @Published var p1Score: Int = 0
    @Published var p2Score: Int = 0
    @Published var state: GameState = .idle
    @Published var showResult = false
    @Published var showRemoveAdsPromo = false
    @Published var showNemesisUnlock = false
    /// Set once the trial runs dry mid-game; acted on at the next goal so a
    /// rally is never cut off halfway.
    private var nemesisTrialOver = false
    private var lastPlayerGoal = Date()
    /// How the game currently in progress was paid for. A credited or owned
    /// game is immune to the trial clock; only a trial game answers to it.
    private var nemesisEntryMode: SettingsStore.NemesisAccess = .owned
    /// nil when no countdown is active. Otherwise the current number being
    /// shown (3, 2, 1). ContentView renders an overlay when non-nil.
    @Published var countdownValue: Int? = nil

    let scene: HockeyScene
    let gameMode: GameMode
    private let settings = SettingsStore.shared

    init(mode: GameMode = .twoPlayer) {
        self.gameMode = mode
        self.scene = HockeyScene()
        self.scene.scaleMode = .resizeFill
        self.scene.gameMode = mode
        scene.onGoalScored = { [weak self] scorer in
            Task { @MainActor [weak self] in self?.handleGoal(by: scorer) }
        }
        scene.onNemesisTrialTick = { [weak self] seconds in
            Task { @MainActor [weak self] in self?.noteNemesisPlay(seconds) }
        }
    }

    /// Slide NEMESIS's pressure from how the game is actually going, so it
    /// converges on a close contest instead of whatever a fixed setting
    /// happens to be worth against this particular player.
    /// Where a NEMESIS game starts before anything is known about how it is
    /// going. Set firm on purpose — this is the tier above HARD, so the
    /// opening minute should feel like it.
    private static let nemesisAnchor = 0.72
    /// Never fall below roughly HARD's difficulty, whatever the scoreline.
    private static let nemesisFloor = 0.30

    private func updateNemesisPressure() {
        guard gameMode == .vsComputer(.nemesis) else { return }
        var p = Self.nemesisAnchor + PlayerModel.shared.historyOffset

        // Live scoreline: behind means back off, ahead means bear down.
        // Capped so one bad patch can't collapse the whole game.
        p += max(-0.22, min(0.22, Double(p1Score - p2Score) * 0.055))

        // Shutout valve — if the player simply cannot get on the board,
        // ease off inside this game rather than waiting for the next one.
        let dry = Date().timeIntervalSince(lastPlayerGoal)
        if dry > 180 { p -= 0.20 } else if dry > 90 { p -= 0.10 }

        scene.nemesisPressure = CGFloat(max(Self.nemesisFloor, min(1, p)))
    }

    @MainActor
    private func noteNemesisPlay(_ seconds: TimeInterval) {
        settings.addNemesisTrialTime(seconds)
        // Only a game being played ON the trial can be cut short by the trial
        // running out. A game paid for with an ad credit is already bought and
        // must run to its end — checking `nemesisTrialExpired` alone meant the
        // flag switched straight back on a second after resuming, so an earned
        // game ended at the very next goal.
        if nemesisEntryMode == .trial, !settings.hasNemesis, settings.nemesisTrialExpired {
            nemesisTrialOver = true
        }
        // Once a second, so the dry-spell valve can open mid-game rather than
        // only at the next goal — which may be exactly what isn't happening.
        updateNemesisPressure()
    }

    /// Called after the player buys NEMESIS from the trial-ended screen —
    /// picks play back up from the goal that interrupted it.
    /// Called once the player has regained access — bought NEMESIS, or earned
    /// a game with a rewarded ad — from the screen that blocked them.
    ///
    /// Two different situations arrive here: the trial ran out *during* a game
    /// (resume it), or they were refused a new one (start it). Getting this
    /// wrong means someone watches an ad and is dropped back to the menu.
    @MainActor
    func resumeOrRestartNemesis() {
        nemesisTrialOver = false
        scene.resumeGame()

        if case .goalScored(let scorer) = state {
            // The rest of this game is now paid for by whatever they just did,
            // so it stops answering to the trial clock.
            nemesisEntryMode = settings.nemesisAccess
            if settings.nemesisAccess == .credit { settings.spendNemesisGame() }
            scene.resumeAfterGoal(towardPlayer: scorer)
            state = .playing
        } else {
            startGame()   // pays its own entry toll
        }
    }

    func startGame() {
        // Entry check lives here so every route in — first launch, Play Again,
        // resuming after an ad — pays the same toll.
        if gameMode == .vsComputer(.nemesis) {
            let access = settings.nemesisAccess
            switch access {
            case .locked:
                showNemesisUnlock = true
                return
            case .credit:
                settings.spendNemesisGame()
            case .owned, .trial:
                break
            }
            nemesisEntryMode = access
            nemesisTrialOver = false
        }

        p1Score = 0
        p2Score = 0
        state = .playing
        showResult = false
        lastPlayerGoal = Date()
        updateNemesisPressure()
        scene.prepareNewGame()
        runCountdown { [weak self] in
            self?.scene.launchGame()
        }
    }

    func togglePause() {
        if scene.isPaused { scene.resumeGame() } else { scene.pauseGame() }
    }

    /// Run a 3-2-1 countdown, updating @Published countdownValue each tick.
    /// `completion` fires after the final tick — typically used to actually
    /// release the puck into play.
    private func runCountdown(from start: Int = 3, completion: @escaping () -> Void) {
        Task { @MainActor in
            for n in stride(from: start, through: 1, by: -1) {
                self.countdownValue = n
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            self.countdownValue = nil
            completion()
        }
    }

    @MainActor
    private func handleGoal(by scorer: Int) {
        if scorer == 1 { p1Score += 1 } else { p2Score += 1 }
        state = .goalScored(by: scorer)
        if scorer == 1 { lastPlayerGoal = Date() }
        updateNemesisPressure()
        PlayerModel.shared.flush()

        // Trial ran out earlier in this game — stop here rather than mid-rally.
        if nemesisTrialOver, !settings.hasNemesis {
            settings.flushNemesisTrial()
            scene.pauseGame()
            showNemesisUnlock = true
            return
        }

        let target = settings.targetScore
        if p1Score >= target || p2Score >= target {
            let winner = p1Score >= target ? 1 : 2
            state = .gameOver(winner: winner)
            settings.registerResult(winner: winner)
            if gameMode == .vsComputer(.nemesis) {
                PlayerModel.shared.recordGameFinished(playerWon: winner == 1)
            }
            HighScoresStore.shared.add(
                p1Name: settings.player1Name,
                p2Name: settings.player2Name,
                p1Goals: p1Score,
                p2Goals: p2Score
            )
            AdManager.shared.noteRoundCompleted()
            // 1-in-5 chance: show the Remove Ads promo in place of a real
            // interstitial. Promo dismissal triggers the result sheet via
            // showRemoveAdsPromo's didSet-style flow in ContentView.
            if AdManager.shared.shouldShowPromoInsteadOfAd() {
                AdManager.shared.notePromoShown()
                self.showRemoveAdsPromo = true
                return
            }
            AdManager.shared.presentIfAllowed { [weak self] shown in
                guard let self else { return }
                if shown {
                    var token: NSObjectProtocol?
                    token = NotificationCenter.default.addObserver(
                        forName: .adDidDismiss, object: nil, queue: .main
                    ) { [weak self] _ in
                        if let t = token { NotificationCenter.default.removeObserver(t) }
                        // Delay so the interstitial VC fully tears down before SwiftUI
                        // presents the result sheet — otherwise the sheet can fail to
                        // show, leaving a blank screen.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                            self?.showResult = true
                        }
                    }
                } else {
                    self.showResult = true
                }
            }
        } else {
            // Mid-game goal: just hold the GOAL banner briefly then resume —
            // no countdown between points (only on first launch / after an
            // ad / after the remove-ads screen, which all flow through
            // startGame() and that runs the countdown there).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard case .goalScored = self.state else { return }
                self.scene.resumeAfterGoal(towardPlayer: scorer)
                self.state = .playing
            }
        }
    }
}
