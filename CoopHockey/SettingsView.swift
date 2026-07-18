import SwiftUI
#if DEBUG
import GoogleMobileAds
#endif

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

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
        .onChange(of: settings.musicEnabled) { enabled in
            Task { @MainActor in
                if enabled { BGM.shared.play(volume: 0.20) } else { BGM.shared.stop() }
            }
        }
    }
}
