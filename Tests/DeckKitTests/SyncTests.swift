import Foundation
import Testing
@testable import DeckKit

@Suite struct SyncTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let t1 = Date(timeIntervalSince1970: 1_000_100)

    @Test func upsertStampsNewAndChangedItems() {
        var matches: [MatchRecord] = []
        let match = MatchRecord(opponent: "Ana")
        let added = matches.upsertStamped(match, now: t0)
        #expect(added)
        #expect(matches.count == 1)
        #expect(matches[0].updatedAt == t0)

        var changed = matches[0]
        changed.opponent = "Beto"
        let updated = matches.upsertStamped(changed, now: t1)
        #expect(updated)
        #expect(matches.count == 1)
        #expect(matches[0].opponent == "Beto")
        #expect(matches[0].updatedAt == t1)
    }

    @Test func upsertIgnoresUnchangedContent() {
        var matches: [MatchRecord] = []
        matches.upsertStamped(MatchRecord(opponent: "Ana"), now: t0)
        // Misma partida con otra marca de tiempo (o sin ella): no es un cambio.
        var same = matches[0]
        same.updatedAt = nil
        let updated = matches.upsertStamped(same, now: t1)
        #expect(!updated)
        #expect(matches[0].updatedAt == t0)
    }

    @Test func legacyJSONWithoutTimestampDecodes() throws {
        let json = """
        [{"id":"5F1C1D7E-0000-4000-8000-000000000001","date":"2026-10-08T16:20:00Z","result":"win",
          "opponent":"Ana","opponentArchetype":"Gardevoir ex","notes":""}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let matches = try decoder.decode([MatchRecord].self, from: Data(json.utf8))
        #expect(matches.count == 1)
        #expect(matches[0].updatedAt == nil)
    }

    @Test func timestampRoundTrips() throws {
        var entry = JournalEntry(archetypeID: UUID(), title: "Plan", date: t0)
        entry.updatedAt = t1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JournalEntry.self, from: encoder.encode(entry))
        #expect(decoded == entry)
    }

    @Test func deletionLogKeepsLatestDateAndRemovesDone() {
        let a = UUID(), b = UUID()
        var log = DeletionLog()
        log.record(table: "matches", id: a, at: t1)
        log.record(table: "matches", id: a, at: t0)
        log.record(table: "decks", id: b, at: t0)
        #expect(log.tombstones.count == 2)
        #expect(log.tombstones(in: "matches").first?.deletedAt == t1)

        log.remove(log.tombstones(in: "matches"))
        #expect(log.tombstones(in: "matches").isEmpty)
        #expect(log.tombstones(in: "decks").map(\.id) == [b])
    }
}
