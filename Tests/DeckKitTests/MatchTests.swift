import Foundation
import Testing
@testable import DeckKit

@Suite struct MatchStatsTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 10))!
    }

    @Test func recordAndWinRate() {
        let stats = MatchStats([.win, .win, .loss, .tie, .win])
        #expect(stats.wins == 3 && stats.losses == 1 && stats.ties == 1)
        #expect(stats.total == 5)
        #expect(stats.winRate == 0.6)
        #expect(stats.record == "3-1-1")
        #expect(MatchStats([.win, .loss]).record == "1-1")
        #expect(MatchStats().winRate == nil)
    }

    @Test func seasonFilter() {
        let matches = [
            MatchRecord(date: date(2026, 6), result: .win),   // temporada 2026
            MatchRecord(date: date(2026, 7), result: .loss),  // temporada 2027
            MatchRecord(date: date(2027, 2), result: .win),   // temporada 2027
        ]
        #expect(matches.inSeason(2027, calendar: calendar).stats.record == "1-1")
        #expect(matches.inSeason(2026, calendar: calendar).stats.record == "1-0")
        #expect(matches.stats.total == 3)
    }

    @Test func bestNeedsEnoughMatches() {
        let items: [(item: String, stats: MatchStats)] = [
            ("1-0", MatchStats(wins: 1)),
            ("6-2", MatchStats(wins: 6, losses: 2)),
            ("3-1", MatchStats(wins: 3, losses: 1)),
            ("sin partidas", MatchStats()),
        ]
        // 6-2 y 3-1 tienen 75 %: gana el de más partidas; el 1-0 no llega al mínimo.
        #expect(Ranking.best(items)?.item == "6-2")
        // Si nadie llega al mínimo, se usan todos los que jugaron.
        #expect(Ranking.best([("1-0", MatchStats(wins: 1)), ("0-1", MatchStats(losses: 1))])?.item == "1-0")
        #expect(Ranking.best([("nada", MatchStats())]) == nil)
    }

    @Test func codableRoundTrip() throws {
        let match = MatchRecord(date: date(2026, 10), deckID: UUID(), result: .tie, opponent: "Ana",
                                opponentArchetype: "Gardevoir ex", eventID: UUID(), notes: "Mesa 4")
        let data = try JSONEncoder().encode(match)
        #expect(try JSONDecoder().decode(MatchRecord.self, from: data) == match)
    }
}

@Suite struct RoundNumberTests {
    func round(_ text: String?) -> Int? {
        var match = MatchRecord()
        match.round = text
        return match.roundNumber
    }

    @Test func parsesRounds() {
        #expect(round("Ronda 3") == 3)
        #expect(round("R10") == 10)
        #expect(round("round #7") == 7)
        #expect(round("Mesa 4 · Ronda 2") == 2)
        #expect(round("Top 8") == 8)
        #expect(round("5") == 5)
        #expect(round("Final") == nil)
        #expect(round(nil) == nil)
        #expect(round("") == nil)
    }
}

@Suite struct MatchupTests {
    private func match(_ result: MatchResult, _ opponent: String) -> MatchRecord {
        MatchRecord(result: result, opponentArchetype: opponent)
    }

    @Test func groupsByOpponentIgnoringCaseAndSpaces() {
        let table = Matchup.table([
            match(.win, "Gardevoir ex"), match(.loss, "gardevoir ex "), match(.win, "Gardevoir ex"),
            match(.loss, "Lost Box"), match(.tie, "Lost Box"),
            match(.win, "Raging Bolt ex"),
        ])
        #expect(table.map(\.opponent) == ["Gardevoir ex", "Lost Box", "Raging Bolt ex"])
        #expect(table[0].stats == MatchStats(wins: 2, losses: 1))
        #expect(table[1].stats == MatchStats(wins: 0, losses: 1, ties: 1))
        #expect(table[2].stats.winRate == 1)
    }

    @Test func unknownOpponentGoesLast() {
        let table = Matchup.table([match(.win, ""), match(.win, " "), match(.loss, "Dragapult ex")])
        #expect(table.map(\.opponent) == ["Dragapult ex", ""])
        #expect(table[1].stats.total == 2)
    }

    @Test func sameCountSortsByWinRate() {
        let table = Matchup.table([match(.loss, "Gengar"), match(.win, "Charizard ex")])
        #expect(table.map(\.opponent) == ["Charizard ex", "Gengar"])
    }
}
