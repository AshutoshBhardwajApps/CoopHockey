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
        scene.startGame()
    }

    func togglePause() {
        if scene.isPaused { scene.resumeGame() } else { scene.pauseGame() }
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
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard case .goalScored = self.state else { return }
                self.scene.resumeAfterGoal(towardPlayer: scorer)
                self.state = .playing
            }
        }
    }
}
