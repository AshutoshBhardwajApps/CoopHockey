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
                VStack(alignment: .leading, spacing: 4) {
                    Text("\"Game background music loop short\"")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("By ManuelGraf")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("freesound.org/s/410574/")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("License: Creative Commons Attribution 4.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
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
