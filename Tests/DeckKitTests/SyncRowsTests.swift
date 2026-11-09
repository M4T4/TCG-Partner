import Foundation
import Testing
@testable import DeckKit

@Suite struct SyncRowsTests {
    let coder = SyncRowCoder(columns: MatchRecord.syncColumns)
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let t1 = Date(timeIntervalSince1970: 1_700_000_100)

    private func objects(_ data: Data) throws -> [[String: Any]] {
        try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func rowsUseColumnNamesAndExplicitNulls() throws {
        var match = MatchRecord(date: t0, result: .loss, opponent: "Ana", opponentArchetype: "Gardevoir ex", kind: .online)
        match.updatedAt = t1
        let row = try #require(try objects(coder.rows([match])).first)
        #expect(row["opponent_archetype"] as? String == "Gardevoir ex")
        #expect(row["result"] as? String == "loss")
        #expect(row["kind"] as? String == "online")
        // Los nil se mandan como null para que borrar un campo también lo borre en la nube.
        #expect(row["deck_id"] is NSNull)
        #expect(row["battle_log"] is NSNull)
        #expect(row["deleted_at"] is NSNull)
        #expect(row["opponentArchetype"] == nil)
        #expect(row["updated_at"] as? String == SyncDates.string(t1))
        #expect(row.count == MatchRecord.syncColumns.count + 1)
    }

    @Test func legacyItemsGetEpochTimestamp() throws {
        let row = try #require(try objects(coder.rows([MatchRecord(date: t0)])).first)
        #expect(row["updated_at"] as? String == SyncDates.string(SyncDates.legacy))
    }

    @Test func decodesSupabaseRows() throws {
        let json = """
        [{"id":"5f1c1d7e-0000-4000-8000-000000000001","user_id":"11111111-1111-1111-1111-111111111111",
          "date":"2026-10-08T16:20:00+00:00","deck_id":null,"result":"win","opponent":"Ana",
          "opponent_archetype":"Gardevoir ex","event_id":null,"notes":"","kind":"inPerson","battle_log":null,
          "went_first":true,"turns":7,"my_prizes":6,"opponent_prizes":3,"round":"Ronda 2",
          "updated_at":"2026-11-09T18:34:05.123456+00:00","deleted_at":null,
          "server_updated_at":"2026-11-09T18:34:06.5+00:00"}]
        """
        let rows = try coder.decode(MatchRecord.self, from: Data(json.utf8))
        let row = try #require(rows.first)
        #expect(row.item.opponentArchetype == "Gardevoir ex")
        #expect(row.item.kind == .inPerson)
        #expect(row.item.wentFirst == true)
        #expect(row.item.turns == 7)
        #expect(row.item.deckID == nil)
        #expect(row.deletedAt == nil)
        let updated = try #require(row.item.updatedAt)
        #expect(abs(updated.timeIntervalSince1970 - 1_794_249_245.123) < 0.001)
        #expect(row.serverUpdatedAt != nil)
    }

    @Test func roundTripThroughRows() throws {
        var entry = JournalEntry(archetypeID: UUID(), kind: .lesson, title: "Guardar Catcher", opponent: "Gardevoir ex",
                                 matchID: UUID(), pinned: true, date: t0)
        entry.updatedAt = t1
        let coder = SyncRowCoder(columns: JournalEntry.syncColumns)
        let decoded = try coder.decode(JournalEntry.self, from: coder.rows([entry]))
        #expect(decoded.first?.item == entry)
    }

    @Test func mergeNewestWins() {
        let id = UUID()
        var old = MatchRecord(id: id, opponent: "Viejo"); old.updatedAt = t0
        var new = MatchRecord(id: id, opponent: "Nuevo"); new.updatedAt = t1

        var local = [new]
        #expect(!SyncMerge.apply([RemoteRow(item: old)], to: &local).changed)
        #expect(local[0].opponent == "Nuevo")

        local = [old]
        #expect(SyncMerge.apply([RemoteRow(item: new)], to: &local).upserted == [id])
        #expect(local[0].opponent == "Nuevo")
    }

    @Test func mergeAddsAndDeletes() {
        var a = MatchRecord(opponent: "A"); a.updatedAt = t0
        var b = MatchRecord(opponent: "B"); b.updatedAt = t0
        var local = [a]
        let result = SyncMerge.apply([RemoteRow(item: b), RemoteRow(item: a, deletedAt: t1)], to: &local)
        #expect(result.upserted == [b.id])
        #expect(result.removed == [a.id])
        #expect(local.map(\.opponent) == ["B"])
    }

    @Test func deleteDoesNotRemoveNewerLocalEdit() {
        var edited = MatchRecord(opponent: "Editada"); edited.updatedAt = t1
        var local = [edited]
        #expect(!SyncMerge.apply([RemoteRow(item: edited, deletedAt: t0)], to: &local).changed)
        #expect(local.count == 1)
    }

    @Test func pendingDeletionsAreNotRevived() {
        var gone = MatchRecord(opponent: "Borrada aquí"); gone.updatedAt = t0
        var local: [MatchRecord] = []
        #expect(!SyncMerge.apply([RemoteRow(item: gone)], to: &local, pending: [gone.id]).changed)
        #expect(local.isEmpty)
    }

    @Test func pendingPushSelection() {
        var a = MatchRecord(); a.updatedAt = t0
        var b = MatchRecord(); b.updatedAt = t1
        let legacy = MatchRecord()
        #expect(SyncMerge.pending([a, b, legacy], since: nil).count == 3)
        #expect(SyncMerge.pending([a, b, legacy], since: t0).map(\.id) == [b.id])
    }

    @Test func serverDatesWithMicroseconds() throws {
        let date = try #require(SyncDates.date("2026-11-09T18:34:05.123456+00:00"))
        #expect(SyncDates.date("2026-11-09T18:34:05+00:00") != nil)
        #expect(SyncDates.date("2026-11-09T18:34:05.5Z") != nil)
        #expect(SyncDates.date(SyncDates.string(date)) == date)
    }
}
