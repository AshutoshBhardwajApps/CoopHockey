import Foundation
import Combine

enum AIDifficulty: String, CaseIterable, Equatable {
    case easy   = "EASY"
    case medium = "MEDIUM"
    case hard   = "HARD"
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
    }

    func startGame() {
        p1Score = 0
        p2Score = 0
        state = .playing
        showResult = false
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

        let target = settings.targetScore
        if p1Score >= target || p2Score >= target {
            let winner = p1Score >= target ? 1 : 2
            state = .gameOver(winner: winner)
            settings.registerResult(winner: winner)
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
            Task { @MainActor in
                // Hold on the GOAL banner for ~1.6s so the moment registers,
                // then run the 3-2-1 countdown before releasing the puck.
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard case .goalScored = self.state else { return }
                self.state = .playing
                self.runCountdown { [weak self] in
                    self?.scene.resumeAfterGoal(towardPlayer: scorer)
                }
            }
        }
    }
}
