import Foundation
import Testing
@testable import DeckKit

@Suite struct BattleLogTests {
    /// Log real de PTCG Live (derrota de Matt_277 contra 0Naldo0).
    let loss: String = {
        let url = Bundle.module.url(forResource: "battlelog-derrota", withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    @Test func realLog() throws {
        let log = try #require(BattleLogParser.parse(loss))
        #expect(log.players == ["Matt_277", "0Naldo0"])
        #expect(log.winner == "0Naldo0")
        #expect(log.endReason == .prizes)
        #expect(log.isTie == false)
        #expect(log.turns == 10)
        // 0Naldo0 «decided to go second» → empezó Matt_277.
        #expect(log.firstPlayer == "Matt_277")
        #expect(log.prizesTaken == ["Matt_277": 5, "0Naldo0": 6])
    }

    @Test func detectsWhoIAm() throws {
        let log = try #require(BattleLogParser.parse(loss))
        // Sin nombres guardados: la mano inicial con viñetas es la mía.
        #expect(log.revealedPlayer == "Matt_277")
        #expect(log.me() == "Matt_277")
        #expect(log.opponent(of: "Matt_277") == "0Naldo0")
        #expect(log.result(for: "Matt_277") == .loss)
        // Los nombres guardados mandan (sin importar mayúsculas).
        #expect(log.me(knownNames: ["0naldo0"]) == "0Naldo0")
        #expect(log.result(for: "0Naldo0") == .win)
    }

    @Test func opponentPokemon() throws {
        let log = try #require(BattleLogParser.parse(loss))
        let rival = try #require(log.pokemon["0Naldo0"])
        #expect(Set(rival) == ["Budew", "Igglybuff", "Poltchageist"])
        // Lo más visto primero.
        #expect(rival.first == "Poltchageist" || rival.first == "Igglybuff")
        // Las cartas descartadas (Banette, Sinistcha) no cuentan como Pokémon en juego.
        #expect(!rival.contains("Banette"))
        let mine = try #require(log.pokemon["Matt_277"])
        #expect(mine.contains("Alakazam") && mine.contains("Fezandipiti ex") && mine.contains("Dusclops"))
    }

    @Test func otherEndings() throws {
        let win = loss.replacingOccurrences(of: "Opponent took all of their Prize cards. 0Naldo0 wins.",
                                            with: "0Naldo0 conceded. Matt_277 wins.")
        let log = try #require(BattleLogParser.parse(win))
        #expect(log.winner == "Matt_277")
        #expect(log.endReason == .concede)
        #expect(log.result(for: "Matt_277") == .win)

        let unfinished = loss.replacingOccurrences(of: "Opponent took all of their Prize cards. 0Naldo0 wins.", with: "")
        #expect(try #require(BattleLogParser.parse(unfinished)).winner == nil)
    }

    @Test func numberedTurnHeadersAndCurlyApostrophes() throws {
        let log = try #require(BattleLogParser.parse("""
        Mr.Bad won the coin toss.
        Mr.Bad decided to go first.
        Ana drew 7 cards for the opening hand.
        Mr.Bad drew 7 cards for the opening hand.

        Turn # 1 - Mr.Bad’s Turn
        Mr.Bad drew a card.

        Turn # 2 - Ana’s Turn
        Ana drew Iono.
        Ana took 2 Prize cards.
        Mr.Bad conceded. Ana wins.
        """))
        #expect(log.players == ["Mr.Bad", "Ana"])
        #expect(log.turns == 2)
        #expect(log.firstPlayer == "Mr.Bad")
        #expect(log.revealedPlayer == "Ana")
        #expect(log.prizesTaken["Ana"] == 2)
        #expect(log.winner == "Ana")
    }

    @Test func notALog() {
        #expect(BattleLogParser.parse("4 Dreepy TWM 128") == nil)
        #expect(BattleLogParser.parse("") == nil)
    }
}

@Suite struct MatchFromLogTests {
    @Test func applyLogToMatch() throws {
        let url = Bundle.module.url(forResource: "battlelog-derrota", withExtension: "txt", subdirectory: "Fixtures")!
        let log = try #require(BattleLogParser.parse(String(contentsOf: url, encoding: .utf8)))
        var match = MatchRecord(kind: .online)
        match.apply(log, me: "Matt_277")
        #expect(match.result == .loss)
        #expect(match.opponent == "0Naldo0")
        #expect(match.wentFirst == true)
        #expect(match.turns == 10)
        #expect(match.myPrizes == 5 && match.opponentPrizes == 6)
    }

    @Test func oldMatchesDecodeAsInPerson() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","date":0,"result":"win","opponent":"Ana","opponentArchetype":"","notes":""}"#
        let match = try JSONDecoder().decode(MatchRecord.self, from: Data(json.utf8))
        #expect(match.kind == nil && match.currentKind == .inPerson)
    }
}
