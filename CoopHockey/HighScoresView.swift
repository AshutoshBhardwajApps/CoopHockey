import SwiftUI

struct HighScoresView: View {
    @EnvironmentObject var scores: HighScoresStore

    var body: some View {
        List {
            ForEach(scores.results) { result in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(result.winnerName)
                            .font(.headline)
                            .foregroundColor(.yellow)
                        Spacer()
                        Text(result.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("\(result.player1Name): \(result.player1Goals)")
                        Spacer()
                        Text("\(result.player2Name): \(result.player2Goals)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 3)
            }
            .onDelete { scores.delete(at: $0) }
        }
        .navigationTitle("Game History")
        .overlay {
            if scores.results.isEmpty {
                ContentUnavailableView("No games yet",
                                       systemImage: "hockey.puck",
                                       description: Text("Play a game to see results here."))
            }
        }
    }
}
