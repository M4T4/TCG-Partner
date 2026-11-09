import DeckKit
import SwiftUI

/// Estado de un mazo dentro de tu colección.
enum DeckStatus: String, Codable, CaseIterable, Identifiable {
    case ready, testing, idea, retired

    var id: Self { self }

    var title: String {
        switch self {
        case .ready: "Listo para torneo"
        case .testing: "En pruebas"
        case .idea: "Idea"
        case .retired: "Retirado"
        }
    }

    var badge: String {
        switch self {
        case .ready: "LISTO"
        case .testing: "EN PRUEBAS"
        case .idea: "IDEA"
        case .retired: "RETIRADO"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .testing: .orange
        case .idea: .blue
        case .retired: .gray
        }
    }
}

/// Paleta para distinguir arquetipos en la barra lateral y en las gráficas.
enum ArchetypeColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.23, green: 0.51, blue: 0.96)
        case .purple: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .pink: Color(red: 0.93, green: 0.29, blue: 0.60)
        case .red: Color(red: 0.94, green: 0.27, blue: 0.27)
        case .orange: Color(red: 0.98, green: 0.45, blue: 0.09)
        case .yellow: Color(red: 0.92, green: 0.70, blue: 0.03)
        case .green: Color(red: 0.13, green: 0.77, blue: 0.37)
        case .teal: Color(red: 0.08, green: 0.72, blue: 0.65)
        }
    }
}

/// Un arquetipo («Alakazam», «Charizard ex»). Agrupa carpetas de mazos y mazos sueltos.
struct Archetype: Syncable, Codable {
    var id = UUID()
    var name: String
    var color: ArchetypeColor = .blue
    /// 1 o 2 Pokémon para los iconos («Alakazam», «Dusknoir»). `nil` = se deducen del nombre.
    var icons: [String]?
    var notes = ""
    var updatedAt: Date?

    /// Iconos a mostrar: los elegidos o, si no hay, los del nombre («Alakazam / Dusknoir» → los dos).
    var iconNames: [String] {
        if let icons, !icons.isEmpty { return icons }
        return PokemonIcon.split(name)
    }
}

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case league, challenge, cup, regional, special, international, worlds, online, other

    var id: Self { self }

    var title: String {
        switch self {
        case .league: "Liga local"
        case .challenge: "League Challenge"
        case .cup: "League Cup"
        case .regional: "Regional"
        case .special: "Special Event"
        case .international: "Internacional"
        case .worlds: "Mundial"
        case .online: "En línea"
        case .other: "Otro"
        }
    }
}

/// Un torneo o evento al que piensas ir.
struct TournamentEvent: Syncable, Codable {
    var id = UUID()
    var name = ""
    var kind: EventKind = .cup
    var startDate = Date()
    var endDate: Date?
    var location = ""
    /// Enlace del evento (Limitless, RK9, Play! Pokémon…).
    var link = ""
    var cost: Double?
    var currency = "MXN"
    var format: GameFormat = .standard
    var plannedDeckID: UUID?
    var registered = false
    /// Tu posición final y cuántos jugaron (se anotan al terminar el evento).
    var placement: Int?
    var players: Int?
    var notes = ""
    var updatedAt: Date?

    var finish: Placement? { Placement(place: placement, players: players) }

    var url: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    var costText: String? {
        guard let cost else { return nil }
        if cost == 0 { return "Gratis" }
        return cost.formatted(.currency(code: currency).precision(.fractionLength(cost.rounded() == cost ? 0 : 2)))
    }

    /// El mazo que más usaste en el evento o, si no hay partidas, el que planeabas jugar.
    func playedDeckID(in eventMatches: [MatchRecord]) -> UUID? {
        let counts = Dictionary(grouping: eventMatches.compactMap(\.deckID), by: { $0 }).mapValues(\.count)
        return counts.max { ($0.value, $1.key.uuidString) < ($1.value, $0.key.uuidString) }?.key ?? plannedDeckID
    }

    /// El evento sigue por delante si aún no termina el día en que acaba.
    func isUpcoming(now: Date = Date()) -> Bool {
        (endDate ?? startDate) >= Calendar.current.startOfDay(for: now)
    }
}

/// Lista de elementos guardada como un JSON en Application Support (partidas, eventos, arquetipos).
/// Cada cambio actualiza `updatedAt` y cada borrado se anota en `DeletionLogStore`, para sincronizar.
@MainActor
final class CollectionStore<Item: Syncable & Codable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published var errorMessage: String?
    let file: URL
    /// Tabla de la nube con los mismos elementos («matches», «events»…).
    let table: String
    private let deletions: DeletionLogStore

    init(fileName: String, table: String, folder: URL = DeckStore.supportFolder, deletions: DeletionLogStore? = nil) {
        file = folder.appendingPathComponent(fileName)
        self.table = table
        self.deletions = deletions ?? .shared
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([Item].self, from: Data(contentsOf: file))
        } catch {
            errorMessage = "No se pudo leer \(fileName): \(error.localizedDescription)"
        }
    }

    /// Aplica cambios llegados de la nube, sin cambiar sus fechas ni anotarlos como borrados aquí.
    func applyRemote(_ rows: [RemoteRow<Item>], pending: Set<UUID>) {
        var updated = items
        guard SyncMerge.apply(rows, to: &updated, pending: pending).changed else { return }
        items = updated
        write()
    }

    func item(_ id: UUID?) -> Item? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Añade el elemento o reemplaza el que tenga el mismo id.
    func save(_ item: Item) {
        if items.upsertStamped(item) { write() }
    }

    func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard var item = item(id) else { return }
        change(&item)
        save(item)
    }

    func delete(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        deletions.record(table: table, id: id)
        write()
    }

    /// Cambia varios elementos y escribe una sola vez.
    func updateAll(where matches: (Item) -> Bool, _ change: (inout Item) -> Void) {
        var changed = false
        let now = Date()
        for index in items.indices where matches(items[index]) {
            var item = items[index]
            change(&item)
            guard item.withoutTimestamp != items[index].withoutTimestamp else { continue }
            item.updatedAt = now
            items[index] = item
            changed = true
        }
        if changed { write() }
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(items).write(to: file, options: .atomic)
        } catch {
            errorMessage = "No se pudo guardar \(file.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

typealias ArchetypeStore = CollectionStore<Archetype>
typealias MatchStore = CollectionStore<MatchRecord>
typealias EventStore = CollectionStore<TournamentEvent>
typealias JournalStore = CollectionStore<JournalEntry>
