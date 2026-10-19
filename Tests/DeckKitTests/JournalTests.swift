import Foundation
import Testing
@testable import DeckKit

@Suite struct JournalTests {
    let archetype = UUID()

    private func entry(_ kind: JournalKind, _ title: String, _ body: String = "", opponent: String = "",
                       pinned: Bool = false, ago: TimeInterval) -> JournalEntry {
        JournalEntry(archetypeID: archetype, kind: kind, title: title, body: body, opponent: opponent,
                     pinned: pinned, date: Date(timeIntervalSince1970: 1_000_000 - ago))
    }

    @Test func titleFallsBackToFirstLine() {
        let untitled = JournalEntry(archetypeID: archetype, body: "\n  Guardar Counter Catcher  \nPara el último premio.")
        #expect(untitled.displayTitle == "Guardar Counter Catcher")
        #expect(untitled.preview == "Para el último premio.")
        #expect(JournalEntry(archetypeID: archetype).displayTitle == "Sin título")
        #expect(JournalEntry(archetypeID: archetype, body: "  \n ").isEmpty)
        let titled = JournalEntry(archetypeID: archetype, title: "Mulligan", body: "Línea 1\nLínea 2")
        #expect(titled.preview == "Línea 1 Línea 2")
    }

    @Test func pinnedFirstThenNewest() {
        let old = entry(.note, "Vieja", ago: 300)
        let new = entry(.note, "Nueva", ago: 10)
        let pinned = entry(.guide, "Plan de juego", pinned: true, ago: 900)
        #expect(JournalEntry.filter([old, new, pinned]).map(\.title) == ["Plan de juego", "Nueva", "Vieja"])
    }

    @Test func filterByKindAndText() {
        let entries = [
            entry(.lesson, "Contra Gardevoir", "Guardar el Counter Catcher", opponent: "Gardevoir ex", ago: 1),
            entry(.lesson, "Contra Dragapult", "Bench barrier", opponent: "Dragapult ex", ago: 2),
            entry(.guide, "Plan general", "Mulligan agresivo, evolución rápida", ago: 3),
        ]
        #expect(JournalEntry.filter(entries, kind: .lesson).count == 2)
        #expect(JournalEntry.filter(entries, query: "gardevoir").map(\.title) == ["Contra Gardevoir"])
        // Sin acentos ni mayúsculas, y todas las palabras deben aparecer.
        #expect(JournalEntry.filter(entries, query: "EVOLUCION rapida").map(\.title) == ["Plan general"])
        #expect(JournalEntry.filter(entries, query: "dragapult mulligan").isEmpty)
        #expect(JournalEntry.filter(entries, kind: .guide, query: "gardevoir").isEmpty)
    }
}
