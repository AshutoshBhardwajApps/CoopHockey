import SwiftUI
#if DEBUG
import GoogleMobileAds
import AdSupport
import AppTrackingTransparency
#endif

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var gameCenter: GameCenterManager

    #if DEBUG
    /// The raw IDFA, or an explanation of why there isn't one. All-zeros is
    /// what you get when tracking is denied, and it is useless to AdMob — so
    /// say that rather than handing over a string of noughts to paste.
    private static var advertisingIdentifier: String {
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard status == .authorized else {
            return "unavailable — ATT is \(attLabel(status)), allow tracking first"
        }
        let id = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        return id == "00000000-0000-0000-0000-000000000000"
            ? "all zeros — tracking is restricted on this device"
            : id
    }

    private static func attLabel(_ s: ATTrackingManager.AuthorizationStatus) -> String {
        switch s {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "not determined"
        @unknown default:    return "unknown"
        }
    }
    #endif

    var body: some View {
        Form {
            Section("PLAYER NAMES") {
                TextField("Player 1", text: $settings.player1Name)
                TextField("Player 2", text: $settings.player2Name)
            }

            Section("GAME") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First to score")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("Goals to win", selection: $settings.targetScore) {
                        ForEach(SettingsStore.targetScoreOptions, id: \.self) { n in
                            Text("\(n) goals").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }

            Section("SOUND") {
                Toggle("Sound Effects",    isOn: $settings.effectsEnabled)
                Toggle("Background Music", isOn: $settings.musicEnabled)
            }

            Section("ADS") {
                if settings.hasRemovedAds {
                    Label("Ads removed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button {
                        Task { await purchaseManager.buyRemoveAds() }
                    } label: {
                        HStack {
                            if purchaseManager.isLoading { ProgressView() }
                            else { Text("Remove Ads") }
                        }
                    }
                    .disabled(purchaseManager.isLoading)

                    Button("Restore Purchases") {
                        Task { await purchaseManager.restorePurchases() }
                    }
                    .disabled(purchaseManager.isLoading)

                    if let msg = purchaseManager.errorMessage {
                        Text(msg).font(.footnote).foregroundColor(.red)
                    }
                }
            }

            #if DEBUG
            Section("DEBUG") {
                Button("Reset NEMESIS trial + profile") {
                    settings.resetNemesisTrial()
                    PlayerModel.shared.reset()
                }
                Button("Expire trial now (jump to paywall)") {
                    settings.expireNemesisTrial()
                }
                Text("Credits: \(settings.nemesisGameCredits) · "
                     + "Free game: \(settings.hasUsedFreeNemesisGame ? "spent" : "available") · "
                     + "studied \(PlayerModel.shared.gamesStudied) games · "
                     + "history offset \(String(format: "%+.2f", PlayerModel.shared.historyOffset))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Separates "nobody tapped" from "taps failed to present" —
                // the ambiguity AdMob's dashboard cannot resolve.
                Text("Rewarded: \(AdManager.shared.rewardedPresentAttempts) attempts · "
                     + "\(AdManager.shared.rewardedImpressions) impressions")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button("Reset consent (UMP form shows next launch)") {
                    ConsentManager.shared.reset()
                }

                // IDFA for registering this device in the AdMob console.
                // Console registration is account-side, so unlike the hash in
                // AppDelegate it protects every installed build — including
                // ones already on the App Store with a stale hash.
                //
                // Reads all zeros unless tracking is authorised; that is also
                // why the hashed ID drifted in the first place.
                Button {
                    UIPasteboard.general.string = Self.advertisingIdentifier
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy IDFA (for AdMob test device)")
                        Text(Self.advertisingIdentifier)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Button("Ad Inspector") {
                    let scenes = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                    guard let root = scenes.first?.windows
                        .first(where: { $0.isKeyWindow })?.rootViewController else { return }
                    var top = root
                    while let presented = top.presentedViewController { top = presented }
                    MobileAds.shared.presentAdInspector(from: top) { error in
                        if let error { print("[AdInspector] \(error.localizedDescription)") }
                    }
                }
            }
            #endif

            Section("GAME CENTER") {
                Button {
                    gameCenter.showLeaderboards()
                } label: {
                    HStack {
                        Image(systemName: "trophy")
                        Text("Leaderboards")
                        Spacer()
                        if !gameCenter.isAuthenticated {
                            Text("Not signed in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(!gameCenter.isAuthenticated)
            }

            Section("ABOUT") {
                NavigationLink {
                    CreditsView()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Credits")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task { await purchaseManager.loadProducts() }
        .onChange(of: settings.musicEnabled) { _, enabled in
            Task { @MainActor in
                if enabled { BGM.shared.play() } else { BGM.shared.stop() }
            }
        }
    }
}
