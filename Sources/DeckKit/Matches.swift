import Foundation

public enum MatchResult: String, Codable, CaseIterable, Sendable, Identifiable {
    case win, loss, tie

    public var id: Self { self }

    public var title: String {
        switch self {
        case .win: "Victoria"
        case .loss: "Derrota"
        case .tie: "Empate"
        }
    }
}

/// Dónde se jugó la partida.
public enum MatchKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// En el simulador Pokémon TCG Live.
    case online
    /// En persona: liga, torneo, con amigos…
    case inPerson

    public var id: Self { self }

    public var title: String {
        switch self {
        case .online: "PTCG Live"
        case .inPerson: "Presencial"
        }
    }
}

/// Una partida registrada.
public struct MatchRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// Mazo con el que jugué (`nil` si ya no existe o no se indicó).
    public var deckID: UUID?
    public var result: MatchResult
    public var opponent: String
    /// Lo que jugaba el rival, en texto libre («Gardevoir ex»).
    public var opponentArchetype: String
    public var eventID: UUID?
    public var notes: String
    /// `nil` en partidas registradas antes de que existiera el tipo (se tratan como presenciales).
    public var kind: MatchKind?
    /// Battle log completo de PTCG Live.
    public var battleLog: String?
    /// Si jugué el primer turno.
    public var wentFirst: Bool?
    public var turns: Int?
    public var myPrizes: Int?
    public var opponentPrizes: Int?
    /// Ronda o mesa en partidas presenciales («Ronda 3», «Mesa 12»).
    public var round: String?

    public var currentKind: MatchKind { kind ?? .inPerson }

    /// Número de ronda para ordenar: «Ronda 3» → 3, «R10» → 10, «Mesa 4 · Ronda 2» → 2.
    /// Si el texto menciona una ronda se usa ese número; si no, el primero que aparezca.
    public var roundNumber: Int? {
        guard let round, !round.isEmpty else { return nil }
        let lower = round.lowercased()
        for marker in ["ronda", "round", "r"] {
            if let range = lower.range(of: "\\b\(marker)\\s*#?\\s*(\\d+)", options: .regularExpression) {
                return Int(lower[range].filter(\.isNumber))
            }
        }
        guard let range = lower.range(of: "\\d+", options: .regularExpression) else { return nil }
        return Int(lower[range])
    }

    public init(id: UUID = UUID(), date: Date = Date(), deckID: UUID? = nil, result: MatchResult = .win,
                opponent: String = "", opponentArchetype: String = "", eventID: UUID? = nil, notes: String = "",
                kind: MatchKind? = nil) {
        self.id = id
        self.date = date
        self.deckID = deckID
        self.result = result
        self.opponent = opponent
        self.opponentArchetype = opponentArchetype
        self.eventID = eventID
        self.notes = notes
        self.kind = kind
    }

    /// Rellena la partida con lo que dice el battle log, desde el punto de vista de `me`.
    public mutating func apply(_ log: BattleLogSummary, me: String) {
        if let result = log.result(for: me) { self.result = result }
        if let opponent = log.opponent(of: me) { self.opponent = opponent }
        wentFirst = log.firstPlayer.map { $0 == me }
        turns = log.turns
        myPrizes = log.prizesTaken[me] ?? 0
        opponentPrizes = log.opponent(of: me).map { log.prizesTaken[$0] ?? 0 }
    }
}

/// Récord de victorias, derrotas y empates.
public struct MatchStats: Hashable, Sendable {
    public var wins = 0
    public var losses = 0
    public var ties = 0

    public init(wins: Int = 0, losses: Int = 0, ties: Int = 0) {
        self.wins = wins
        self.losses = losses
        self.ties = ties
    }

    public init<S: Sequence>(_ results: S) where S.Element == MatchResult {
        for result in results {
            switch result {
            case .win: wins += 1
            case .loss: losses += 1
            case .tie: ties += 1
            }
        }
    }

    public var total: Int { wins + losses + ties }

    /// Victorias entre partidas jugadas (los empates cuentan como no ganadas). `nil` sin partidas.
    public var winRate: Double? { total == 0 ? nil : Double(wins) / Double(total) }

    /// «24-8» o «24-8-2» si hay empates.
    public var record: String { ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)" }
}

public extension Sequence where Element == MatchRecord {
    var stats: MatchStats { MatchStats(map(\.result)) }

    /// Partidas de una temporada de Play! Pokémon (ver `AgeDivision.season`).
    func inSeason(_ season: Int, calendar: Calendar = .current) -> [MatchRecord] {
        filter { AgeDivision.season(on: $0.date, calendar: calendar) == season }
    }
}

/// Tu récord contra un mazo rival («Gardevoir ex», «Lost Box»).
public struct Matchup: Hashable, Sendable {
    /// Nombre del mazo rival; vacío si no lo anotaste.
    public var opponent: String
    public var stats: MatchStats

    public init(opponent: String, stats: MatchStats) {
        self.opponent = opponent
        self.stats = stats
    }

    /// Agrupa las partidas por mazo rival, sin importar mayúsculas ni espacios
    /// («gardevoir ex » y «Gardevoir ex» son el mismo). Muestra la forma más escrita.
    /// Orden: más partidas primero; luego mejor win rate y nombre. Los que no tienen rival anotado van al final.
    public static func table<S: Sequence>(_ matches: S) -> [Matchup] where S.Element == MatchRecord {
        var groups: [String: (names: [String: Int], results: [MatchResult])] = [:]
        for match in matches {
            let name = match.opponentArchetype.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            groups[key, default: ([:], [])].names[name, default: 0] += 1
            groups[key, default: ([:], [])].results.append(match.result)
        }
        return groups.map { _, group in
            let name = group.names.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
            return Matchup(opponent: name, stats: MatchStats(group.results))
        }
        .sorted { a, b in
            if a.opponent.isEmpty != b.opponent.isEmpty { return b.opponent.isEmpty }
            if a.stats.total != b.stats.total { return a.stats.total > b.stats.total }
            if a.stats.winRate != b.stats.winRate { return (a.stats.winRate ?? 0) > (b.stats.winRate ?? 0) }
            return a.opponent.localizedStandardCompare(b.opponent) == .orderedAscending
        }
    }
}

public enum Ranking {
    /// El elemento con mejor porcentaje de victorias. Solo cuenta a quienes tienen al menos
    /// `minMatches` partidas (para que un 1-0 no gane); si nadie llega, usa todos los que tengan alguna.
    /// Empates en porcentaje: gana el que tiene más partidas.
    public static func best<T>(_ items: [(item: T, stats: MatchStats)], minMatches: Int = 3) -> (item: T, stats: MatchStats)? {
        let played = items.filter { $0.stats.total > 0 }
        let eligible = played.filter { $0.stats.total >= minMatches }
        return (eligible.isEmpty ? played : eligible).max { a, b in
            (a.stats.winRate ?? 0, a.stats.total) < (b.stats.winRate ?? 0, b.stats.total)
        }
    }
}
