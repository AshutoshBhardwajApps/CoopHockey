import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("GAME") {
                Text("COOP AirHockey")
                    .font(.headline)
                Text("A two-player local air hockey game for iPhone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section("DEVELOPMENT") {
                LabeledContent("Developer", value: "Ashutosh Bhardwaj")
            }

            Section("MUSIC") {
                Text("Background music licensed for use in this app.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("FRAMEWORKS") {
                LabeledContent("Ads",      value: "Google Mobile Ads SDK")
                LabeledContent("Payments", value: "StoreKit")
                LabeledContent("Game",     value: "SpriteKit")
            }
        }
        .navigationTitle("Credits")
    }
}
