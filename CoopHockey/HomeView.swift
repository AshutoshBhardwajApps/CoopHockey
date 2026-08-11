import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scores: HighScoresStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var activeGameMode: GameMode? = nil
    @State private var showDifficulty = false
    @State private var showRemoveAdsSheet = false
    @State private var showNemesisSheet = false
    /// Mirrored into @State because SettingsStore doesn't publish the trial
    /// clock — refreshed whenever this screen comes back into view.
    @State private var trialRemaining: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.07, blue: 0.14)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Title
                    VStack(spacing: 2) {
                        Text("COOP")
                            .font(.system(size: 58, weight: .black))
                            .foregroundColor(.white)
                        Text("AIRHOCKEY")
                            .font(.system(size: 46, weight: .black))
                            .foregroundColor(.cyan)
                    }
                    .padding(.bottom, 36)

                    // Player names
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text(settings.player1Name)
                                .font(.headline)
                                .foregroundColor(Theme.player1Color)
                            Text("P1")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Text("VS")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white.opacity(0.6))

                        VStack(spacing: 4) {
                            Text(showDifficulty ? "CPU" : settings.player2Name)
                                .font(.headline)
                                .foregroundColor(Theme.player2Color)
                            Text(showDifficulty ? "CPU" : "P2")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: showDifficulty)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)

                    // Mode / difficulty buttons
                    VStack(spacing: 14) {
                        if !showDifficulty {
                            Button {
                                activeGameMode = .twoPlayer
                            } label: {
                                HomeButtonLabel(title: "TWO PLAYERS", color: .cyan)
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDifficulty = true
                                }
                            } label: {
                                HomeButtonLabel(title: "VS COMPUTER", color: Theme.player2Color)
                            }
                        } else {
                            Text("SELECT DIFFICULTY")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(2)

                            ForEach(AIDifficulty.freeCases, id: \.self) { diff in
                                Button {
                                    activeGameMode = .vsComputer(diff)
                                } label: {
                                    HomeButtonLabel(
                                        title: diff.rawValue,
                                        color: difficultyColor(diff)
                                    )
                                }
                            }

                            // NEMESIS: free until the trial is spent, then the
                            // button becomes the store page.
                            Button {
                                if settings.canPlayNemesis {
                                    activeGameMode = .vsComputer(.nemesis)
                                } else {
                                    showNemesisSheet = true
                                }
                            } label: {
                                HomeButtonLabel(
                                    title: AIDifficulty.nemesis.rawValue,
                                    color: Theme.nemesisColor,
                                    locked: !settings.canPlayNemesis,
                                    badge: nemesisBadge
                                )
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDifficulty = false
                                }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)

                    // Settings / History
                    HStack(spacing: 32) {
                        NavigationLink(destination: SettingsView()) {
                            VStack(spacing: 6) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                Text("Settings")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.75))
                        }

                        NavigationLink(destination: HighScoresView()) {
                            VStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .font(.title2)
                                Text("History")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.bottom, 16)

                    // Win counter
                    if settings.totalGamesPlayed > 0 {
                        Text("Games: \(settings.totalGamesPlayed)  •  P1 \(settings.p1WinsTotal)  –  P2 \(settings.p2WinsTotal)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Remove Ads pill — visible only until purchased.
                    if !settings.hasRemovedAds {
                        Button {
                            showRemoveAdsSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "nosign")
                                Text("Remove Ads")
                                if let price = purchaseManager.localizedPrice {
                                    Text("· \(price)")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                            )
                        }
                        .padding(.top, 12)
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if settings.musicEnabled { BGM.shared.play(volume: 0.20) } else { BGM.shared.stop() }
                showDifficulty = false
                trialRemaining = Int(settings.nemesisTrialRemaining)
            }
        }
        .fullScreenCover(item: $activeGameMode, onDismiss: {
            trialRemaining = Int(settings.nemesisTrialRemaining)
        }) { mode in
            ContentView(gameMode: mode)
                .environmentObject(settings)
                .environmentObject(scores)
                .environmentObject(purchaseManager)
        }
        .fullScreenCover(isPresented: $showRemoveAdsSheet) {
            RemoveAdsPromoView(onDismiss: { showRemoveAdsSheet = false })
                .environmentObject(settings)
                .environmentObject(purchaseManager)
        }
        .fullScreenCover(isPresented: $showNemesisSheet) {
            NemesisUnlockView(onDismiss: { showNemesisSheet = false })
                .environmentObject(settings)
                .environmentObject(purchaseManager)
        }
    }

    /// Trial state under the NEMESIS button: how much free play is left, or
    /// nothing at all once it's bought.
    private var nemesisBadge: String? {
        if settings.hasNemesis { return nil }
        let left = trialRemaining
        if left > 0 {
            if left >= Int(SettingsStore.nemesisTrialLimit) { return "FREE · 15 MIN" }
            if left < 60 { return "UNDER 1 MIN LEFT" }
            return "\(Int(ceil(Double(left) / 60))) MIN LEFT"
        }
        let credits = settings.nemesisGameCredits
        if credits > 0 { return credits == 1 ? "1 GAME READY" : "\(credits) GAMES READY" }
        return "WATCH AD OR UNLOCK"
    }

    private func difficultyColor(_ diff: AIDifficulty) -> Color {
        switch diff {
        case .easy:    return Color(red: 0.2, green: 0.75, blue: 0.3)
        case .medium:  return Color(red: 1.0, green: 0.65, blue: 0.0)
        case .hard:    return Color(red: 0.9, green: 0.2,  blue: 0.2)
        case .nemesis: return Theme.nemesisColor
        }
    }
}

private struct HomeButtonLabel: View {
    let title: String
    let color: Color
    var locked: Bool = false
    var badge: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 17, weight: .black))
                }
                Text(title)
                    .font(.system(size: 22, weight: .black))
            }
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .opacity(0.65)
            }
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, badge == nil ? 18 : 13)
        .background(color)
        .cornerRadius(16)
    }
}
