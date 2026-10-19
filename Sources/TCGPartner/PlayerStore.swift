import DeckKit
import Foundation

/// Un jugador guardado, para no volver a escribir sus datos cada vez que imprime.
struct Player: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var playerID: String
    var birthDate: Date?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Jugador sin nombre" : trimmed
    }

    func info(format: GameFormat) -> PlayerInfo {
        PlayerInfo(name: name.trimmingCharacters(in: .whitespaces),
                   playerID: playerID.trimmingCharacters(in: .whitespaces),
                   birthDate: birthDate, format: format)
    }
}

/// Los jugadores guardados, en `~/Library/Application Support/TCGPartner/players.json`.
@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published var errorMessage: String?

    let file: URL

    init(file: URL = DeckStore.supportFolder.appendingPathComponent("players.json")) {
        self.file = file
        load()
        importLegacyPlayer()
    }

    func player(_ id: Player.ID) -> Player? {
        players.first { $0.id == id }
    }

    @discardableResult
    func add(name: String = "", playerID: String = "", birthDate: Date? = nil) -> Player {
        let player = Player(id: UUID(), name: name, playerID: playerID, birthDate: birthDate)
        players.append(player)
        save()
        return player
    }

    func update(_ id: Player.ID, _ change: (inout Player) -> Void) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        var player = players[index]
        change(&player)
        guard player != players[index] else { return }
        players[index] = player
        save()
    }

    func delete(_ id: Player.ID) {
        players.removeAll { $0.id == id }
        save()
    }

    /// Ordenados por nombre para el menú desplegable.
    var sorted: [Player] {
        players.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            players = try decoder.decode([Player].self, from: Data(contentsOf: file))
        } catch {
            errorMessage = "No se pudieron leer los jugadores guardados: \(error.localizedDescription)"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(players).write(to: file, options: .atomic)
        } catch {
            errorMessage = "No se pudieron guardar los jugadores: \(error.localizedDescription)"
        }
    }

    /// La versión anterior guardaba un único jugador en las preferencias; se pasa a la lista una sola vez.
    private func importLegacyPlayer() {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "player.name") ?? ""
        let playerID = defaults.string(forKey: "player.id") ?? ""
        let birth = defaults.double(forKey: "player.birthDate")
        defer { ["player.name", "player.id", "player.birthDate"].forEach(defaults.removeObject) }
        guard players.isEmpty, !(name.isEmpty && playerID.isEmpty) else { return }
        let player = add(name: name, playerID: playerID, birthDate: birth == 0 ? nil : Date(timeIntervalSince1970: birth))
        defaults.set(player.id.uuidString, forKey: currentPlayerKey)
    }
}
