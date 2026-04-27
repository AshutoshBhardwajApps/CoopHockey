import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var coordinator: GameCoordinator
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    init(gameMode: GameMode = .twoPlayer) {
        _coordinator = StateObject(wrappedValue: GameCoordinator(mode: gameMode))
    }

    var body: some View {
        ZStack {
            // Stable presenter VC for interstitial ads
            AdPresenter().frame(width: 0, height: 0)

            // Full-screen rink
            SpriteView(scene: coordinator.scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .onAppear { coordinator.startGame() }

            // Scores overlay
            VStack(spacing: 0) {
                // P2 score at top — rotated so it faces the top-seated player
                let p2Label = coordinator.gameMode == .twoPlayer ? settings.player2Name : "CPU"
                ScoreLabel(score: coordinator.p2Score, color: Theme.player2Color,
                           name: p2Label)
                    .rotationEffect(.degrees(180))
                    .padding(.top, 52)

                Spacer()

                // P1 score at bottom
                ScoreLabel(score: coordinator.p1Score, color: Theme.player1Color,
                           name: settings.player1Name)
                    .padding(.bottom, 52)
            }

            // "GOAL!" flash
            if case .goalScored(let scorer) = coordinator.state {
                GoalBanner(scorer: scorer)
            }

            // Pause / exit button
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(16)
                    }
                    Spacer()
                    Button {
                        coordinator.togglePause()
                    } label: {
                        Image(systemName: coordinator.scene.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $coordinator.showResult) {
            ResultView(coordinator: coordinator, onNewGame: {
                coordinator.startGame()
            }, onDismiss: {
                dismiss()
            })
            .environmentObject(settings)
        }
    }
}

// MARK: - Sub-views

private struct ScoreLabel: View {
    let score: Int
    let color: Color
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.50))
        }
    }
}

private struct GoalBanner: View {
    let scorer: Int

    var body: some View {
        Text("GOAL!")
            .font(.system(size: 52, weight: .black, design: .rounded))
            .foregroundColor(scorer == 1 ? Theme.player1Color : Theme.player2Color)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .rotationEffect(scorer == 2 ? .degrees(180) : .zero)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: scorer)
    }
}

struct ResultView: View {
    @ObservedObject var coordinator: GameCoordinator
    @EnvironmentObject var settings: SettingsStore
    let onNewGame: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea()

            if case .gameOver(let winner) = coordinator.state {
                let isVsComputer = coordinator.gameMode != .twoPlayer
                let p2Name = isVsComputer ? "CPU" : settings.player2Name
                let winnerName = winner == 1 ? settings.player1Name : p2Name
                let winnerColor = winner == 1 ? Theme.player1Color : Theme.player2Color

                VStack(spacing: 28) {
                    Text("🏆")
                        .font(.system(size: 80))

                    Text(winnerName)
                        .font(.system(size: 38, weight: .black))
                        .foregroundColor(winnerColor)

                    Text("WINS!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))

                    HStack(spacing: 44) {
                        VStack(spacing: 4) {
                            Text("\(coordinator.p1Score)")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundColor(Theme.player1Color)
                            Text(settings.player1Name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("–")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        VStack(spacing: 4) {
                            Text("\(coordinator.p2Score)")
                                .font(.system(size: 52, weight: .black, design: .rounded))
                                .foregroundColor(Theme.player2Color)
                            Text(p2Name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(spacing: 14) {
                        Button("Play Again") {
                            coordinator.showResult = false
                            onNewGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.large)

                        Button("Back to Menu") { onDismiss() }
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(40)
            }
        }
    }
}
