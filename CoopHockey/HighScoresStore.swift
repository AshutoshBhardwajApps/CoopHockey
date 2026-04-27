import Foundation

struct HockeyResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let player1Name: String
    let player2Name: String
    let player1Goals: Int
    let player2Goals: Int

    var winnerName: String {
        player1Goals > player2Goals ? player1Name : player2Name
    }
}

final class HighScoresStore: ObservableObject {
    static let shared = HighScoresStore()

    @Published private(set) var results: [HockeyResult] = []

    private let key = "h.highScores"
    private let maxResults = 10

    private init() { load() }

    func add(p1Name: String, p2Name: String, p1Goals: Int, p2Goals: Int) {
        let r = HockeyResult(id: UUID(), date: Date(),
                             player1Name: p1Name, player2Name: p2Name,
                             player1Goals: p1Goals, player2Goals: p2Goals)
        results.insert(r, at: 0)
        if results.count > maxResults { results = Array(results.prefix(maxResults)) }
        save()
    }

    func delete(at offsets: IndexSet) {
        results.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HockeyResult].self, from: data)
        else { return }
        results = decoded
    }
}
