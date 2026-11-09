import DeckKit
import Foundation

struct DeckPerformance: Identifiable {
    let deck: Deck
    let archetype: Archetype?
    let stats: MatchStats
    var id: UUID { deck.id }
}

struct ArchetypePerformance: Identifiable {
    /// `nil` = «Sin arquetipo» (mazos sueltos o partidas con mazos borrados).
    let archetype: Archetype?
    let folderCount: Int
    let deckCount: Int
    let stats: MatchStats

    var id: String { archetype?.id.uuidString ?? "sin-arquetipo" }
    var name: String { archetype?.name ?? "Sin arquetipo" }
}

/// Cruza mazos, arquetipos y partidas para el dashboard y las vistas de detalle.
@MainActor
struct Analytics {
    let decks: DeckStore
    let archetypes: ArchetypeStore
    /// Partidas ya filtradas (temporada, arquetipo…).
    let matches: [MatchRecord]

    func archetype(of deckID: UUID?) -> Archetype? {
        guard let deck = deckID.flatMap(decks.deck) else { return nil }
        return archetypes.item(decks.archetypeID(of: deck))
    }

    func stats(forDeck id: UUID) -> MatchStats {
        matches.filter { $0.deckID == id }.stats
    }

    /// Todos los mazos con su récord, los más jugados primero.
    var deckPerformance: [DeckPerformance] {
        let byDeck = Dictionary(grouping: matches, by: \.deckID)
        return decks.decks
            .map { DeckPerformance(deck: $0, archetype: archetypes.item(decks.archetypeID(of: $0)),
                                   stats: (byDeck[$0.id] ?? []).stats) }
            .sorted { ($0.stats.total, $0.deck.modified) > ($1.stats.total, $1.deck.modified) }
    }

    /// Todos los arquetipos (aunque no tengan partidas), los más jugados primero.
    var archetypePerformance: [ArchetypePerformance] {
        let known = Set(archetypes.items.map(\.id))
        let byArchetype = Dictionary(grouping: matches) { match -> UUID? in
            guard let deck = match.deckID.flatMap(decks.deck), let id = decks.archetypeID(of: deck),
                  known.contains(id) else { return nil }
            return id
        }
        var rows = archetypes.items.map { archetype in
            ArchetypePerformance(archetype: archetype, folderCount: decks.folders(of: archetype.id).count,
                                 deckCount: decks.decks(ofArchetype: archetype.id).count,
                                 stats: (byArchetype[archetype.id] ?? []).stats)
        }
        if let orphan = byArchetype[nil], !orphan.isEmpty {
            rows.append(ArchetypePerformance(archetype: nil, folderCount: decks.folders(of: nil).count,
                                             deckCount: decks.decks(ofArchetype: nil).count, stats: orphan.stats))
        }
        return rows.sorted { ($0.stats.total, $1.name) > ($1.stats.total, $0.name) }
    }

    var mostUsedArchetype: ArchetypePerformance? {
        archetypePerformance.first { $0.stats.total > 0 }
    }

    /// El mazo con mejor porcentaje (mínimo 3 partidas si hay alguno que llegue).
    var bestDeck: DeckPerformance? {
        Ranking.best(deckPerformance.map { (item: $0, stats: $0.stats) })?.item
    }
}
