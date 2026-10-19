import Foundation

/// Tu posición final en un torneo («3.º de 64 · Top 4»).
public struct Placement: Hashable, Sendable {
    public var place: Int
    /// Jugadores en el torneo, si lo sabes.
    public var players: Int?

    public init?(place: Int?, players: Int? = nil) {
        guard let place, place > 0 else { return nil }
        self.place = place
        self.players = players.flatMap { $0 > 0 ? $0 : nil }
    }

    /// «1.º», «12.º».
    public var ordinal: String { "\(place).º" }

    /// «3.º de 64» o «3.º» si no sabes cuántos jugaron.
    public var text: String {
        guard let players else { return ordinal }
        return "\(ordinal) de \(players)"
    }

    /// Campeón, finalista o el corte más chico que alcanzaste («Top 4», «Top 8»… hasta Top 256).
    /// Si sabes cuántos jugaron, no se muestra un corte igual o mayor que el torneo (Top 8 de 8 no dice nada).
    public var title: String? {
        switch place {
        case 1: return "Campeón"
        case 2: return "Finalista"
        default:
            var cut = 4
            while cut < place { cut *= 2 }
            guard cut <= 256 else { return nil }
            if let players, cut >= players { return nil }
            return "Top \(cut)"
        }
    }

    /// Mejor resultado primero: posición más alta; a igual posición, el torneo más grande.
    public static func isBetter(_ a: Placement, than b: Placement) -> Bool {
        if a.place != b.place { return a.place < b.place }
        return (a.players ?? 0) > (b.players ?? 0)
    }

    /// Para pintar medallas: 1 oro, 2 plata, 3 y 4 bronce.
    public var medal: Int? { place <= 4 ? min(place, 3) : nil }
}
