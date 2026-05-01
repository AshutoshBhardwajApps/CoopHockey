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
            // Full-screen dark background (extends behind the inset SpriteView)
            Color(red: 0.04, green: 0.13, blue: 0.06).ignoresSafeArea()

            // Stable presenter VC for interstitial ads
            AdPresenter().frame(width: 0, height: 0)

            // Scores — sideways on the right edge, centered in each half so the
            // dashed center line visually separates them. Rendered BEFORE the
            // SpriteView so the puck and mallets (drawn into the SpriteView with
            // a transparent background) visually overlap and hide the scores
            // when they pass over them.
            //
            // Two-player: scores mirror each other (P2 reads from top, P1 from
            // bottom). vsComputer: both scores read from P1's seat since there
            // is no second human looking from the top.
            let isVsComputer = coordinator.gameMode != .twoPlayer
            let p2Label = isVsComputer ? "CPU" : settings.player2Name
            let p2Rotation: Double = isVsComputer ? -90 : 90
            let p2NameFirst = isVsComputer
            GeometryReader { geo in
                let rightX = geo.size.width - 38
                ZStack {
                    ScoreLabel(score: coordinator.p2Score, color: Theme.player2Color, name: p2Label, nameFirst: p2NameFirst)
                        .rotationEffect(.degrees(p2Rotation))
                        .position(x: rightX, y: geo.size.height * 0.45)

                    ScoreLabel(score: coordinator.p1Score, color: Theme.player1Color, name: settings.player1Name, nameFirst: true)
                        .rotationEffect(.degrees(-90))
                        .position(x: rightX, y: geo.size.height * 0.55)
                }
            }
            .ignoresSafeArea()

            // Rink — inset from top/bottom to keep play area away from system gesture zones.
            // .allowsTransparency lets the dark-green Color and the SwiftUI score labels
            // behind this SpriteView show through; without it SwiftUI renders an opaque
            // black backing regardless of the scene's backgroundColor = .clear.
            SpriteView(scene: coordinator.scene, options: [.allowsTransparency])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 52)
                .padding(.bottom, 68)
                .ignoresSafeArea()
                .onAppear {
                    // Guard against re-firing after the interstitial ad dismisses —
                    // re-running startGame() resets state away from .gameOver and
                    // makes the result sheet render blank.
                    if coordinator.state == .idle { coordinator.startGame() }
                }

            // "GOAL!" flash
            if case .goalScored(let scorer) = coordinator.state {
                GoalBanner(scorer: scorer)
            }

            // Pause / exit buttons
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
                .padding(.top, 52)
                Spacer()
            }
            .ignoresSafeArea()
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
    var nameFirst: Bool = false   // true → name above score in the VStack

    var body: some View {
        VStack(spacing: 2) {
            if nameFirst {
                nameText
                scoreText
            } else {
                scoreText
                nameText
            }
        }
    }

    private var scoreText: some View {
        Text("\(score)")
            .font(.system(size: 60, weight: .black, design: .rounded))
            .foregroundColor(color)
    }
    private var nameText: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white.opacity(0.50))
    }
}

private struct GoalBanner: View {
    let scorer: Int

    var body: some View {
        Text("GOAL!")
            .font(.system(size: 52, weight: .black, design: .rounded))
            .foregroundColor(scorer == 1 ? Theme.player1Color : Theme.player2Color)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .rotationEffect(scorer == 2 ? .degrees(90) : .zero)
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
