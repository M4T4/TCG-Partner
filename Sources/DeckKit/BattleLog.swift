import Foundation

/// Cómo terminó una partida de PTCG Live, según la última línea del battle log.
public enum BattleEndReason: String, Codable, Sendable {
    case prizes, concede, noPokemon, deckOut, other

    public var title: String {
        switch self {
        case .prizes: "tomó todos sus premios"
        case .concede: "rendición"
        case .noPokemon: "sin Pokémon en juego"
        case .deckOut: "sin cartas en el mazo"
        case .other: "fin de la partida"
        }
    }
}

/// Lo que se puede saber de una partida a partir del battle log de PTCG Live.
public struct BattleLogSummary: Sendable, Equatable {
    /// Los dos jugadores, en el orden en que aparecen.
    public var players: [String] = []
    public var winner: String?
    public var isTie = false
    public var endReason: BattleEndReason?
    /// Quién jugó el primer turno.
    public var firstPlayer: String?
    public var turns = 0
    /// Jugador cuyas cartas ocultas aparecen en el log (mano inicial, robos con nombre): casi seguro eres tú.
    public var revealedPlayer: String?
    public var prizesTaken: [String: Int] = [:]
    /// Pokémon que puso en juego cada jugador, los más vistos primero.
    public var pokemon: [String: [String]] = [:]

    /// Cuál de los dos jugadores eres: primero por tus nombres de usuario guardados, luego por las cartas reveladas.
    public func me(knownNames: [String] = []) -> String? {
        if let known = players.first(where: { player in
            knownNames.contains { $0.caseInsensitiveCompare(player) == .orderedSame }
        }) {
            return known
        }
        return revealedPlayer
    }

    public func opponent(of me: String) -> String? {
        players.first { $0 != me }
    }

    public func result(for me: String) -> MatchResult? {
        if isTie { return .tie }
        guard let winner else { return nil }
        return winner == me ? .win : .loss
    }
}

/// Lee el battle log que se copia en PTCG Live (resumen de la partida › pestaña «Battle Log»).
public enum BattleLogParser {
    /// `nil` si el texto no parece un battle log (no aparecen dos jugadores).
    public static func parse(_ text: String) -> BattleLogSummary? {
        // PTCG Live mezcla el apóstrofo recto y el curvo («Matt_277’s Duskull»).
        let lines = text.replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var summary = BattleLogSummary()
        func addPlayer(_ name: String) {
            let name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !summary.players.contains(name), summary.players.count < 2 { summary.players.append(name) }
        }

        // 1. Jugadores: reparto inicial y moneda.
        for line in lines {
            if let name = line.capture(#"^(.+) drew 7 cards for the opening hand\.$"#) { addPlayer(name) }
            if let name = line.capture(#"^(.+) won the coin toss\.$"#) { addPlayer(name) }
            if let name = line.capture(#"^(.+) chose (?:heads|tails) for the opening coin flip\.$"#) { addPlayer(name) }
        }
        // Encabezados de turno («Matt_277's Turn» o «Turn # 3 - Matt_277's Turn»).
        let turnHeader = #"^(?:Turn # ?\d+ - )?(.+)'s Turn$"#
        for line in lines {
            if let name = line.capture(turnHeader) { addPlayer(name) }
        }
        guard summary.players.count == 2 else { return nil }
        let players = summary.players

        // 2. Turnos y quién empezó.
        let turnOwners = lines.compactMap { line in line.capture(turnHeader).flatMap { players.contains($0) ? $0 : nil } }
        summary.turns = turnOwners.count
        summary.firstPlayer = turnOwners.first
        for line in lines {
            if let name = line.capture(#"^(.+) decided to go (?:first|second)\.$"#), players.contains(name) {
                let first = line.hasSuffix("first.")
                summary.firstPlayer = first ? name : players.first { $0 != name }
            }
        }

        // 3. Quién eres: tu mano inicial aparece con viñetas y tus robos dicen el nombre de la carta.
        var revealScore: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            if let name = line.capture(#"^(.+) drew 7 cards for the opening hand\.$"#),
               lines.dropFirst(index + 1).prefix(2).contains(where: { $0.hasPrefix("•") }) {
                revealScore[name, default: 0] += 10
            }
            for player in players {
                guard line.hasPrefix("\(player) drew ") || line.hasPrefix("- \(player) drew ") else { continue }
                let rest = line.components(separatedBy: "\(player) drew ").last ?? ""
                if rest.hasPrefix("a card") || rest.range(of: #"^\d+ (?:more )?cards?"#, options: .regularExpression) != nil { continue }
                revealScore[player, default: 0] += 1
            }
        }
        if let best = revealScore.max(by: { $0.value < $1.value }),
           revealScore.values.filter({ $0 == best.value }).count == 1 {
            summary.revealedPlayer = best.key
        }

        // 4. Premios.
        for line in lines {
            for player in players {
                if line == "\(player) took a Prize card." {
                    summary.prizesTaken[player, default: 0] += 1
                } else if let count = line.capture("^\(NSRegularExpression.escapedPattern(for: player)) took (\\d+) Prize cards\\.$").flatMap(Int.init) {
                    summary.prizesTaken[player, default: 0] += count
                }
            }
        }

        // 5. Pokémon en juego de cada jugador.
        var seen: [String: [String: Int]] = [:]
        func saw(_ player: String, _ card: String) {
            let card = card.trimmingCharacters(in: .whitespaces)
            guard !card.isEmpty else { return }
            seen[player, default: [:]][card, default: 0] += 1
        }
        var benchFromBullets: String?
        for line in lines {
            if line.hasPrefix("•"), let player = benchFromBullets {
                line.dropFirst().split(separator: ",").forEach { saw(player, String($0)) }
                benchFromBullets = nil
                continue
            }
            benchFromBullets = nil
            for player in players {
                let p = NSRegularExpression.escapedPattern(for: player)
                if let card = line.capture("^(?:- )?\(p) played (.+) to the (?:Active Spot|Bench)\\.$") { saw(player, card) }
                if let card = line.capture("^\(p)'s (.+?) (?:used .+|was Knocked Out!|is now in the Active Spot\\.)$") { saw(player, card) }
                if let groups = line.captures("^(?:- )?\(p) evolved (.+?) to (.+?) (?:in the Active Spot|on the Bench)\\.$") {
                    groups.forEach { saw(player, $0) }
                }
                if let card = line.capture("^(?:- )?\(p) drew (.+) and played it to the Bench\\.$") { saw(player, card) }
                if line.range(of: "^(?:- )?\(p) drew \\d+ cards and played them to the Bench\\.$", options: .regularExpression) != nil {
                    benchFromBullets = player
                }
            }
        }
        summary.pokemon = seen.mapValues { counts in
            counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        }

        // 6. Resultado: la última línea que dice quién ganó.
        for line in lines.reversed() where !line.isEmpty {
            if let winner = players.first(where: { line.hasSuffix("\($0) wins.") || line.hasSuffix("\($0) won.") }) {
                summary.winner = winner
                let lower = line.lowercased()
                summary.endReason = lower.contains("prize") ? .prizes
                    : lower.contains("conceded") || lower.contains("concede") ? .concede
                    : lower.contains("no pokémon") || lower.contains("no more pokémon") || lower.contains("in play") ? .noPokemon
                    : lower.contains("deck") ? .deckOut
                    : .other
                break
            }
            let lower = line.lowercased()
            if lower.contains("tie") || lower.contains("draw.") || lower.contains("in a draw") {
                summary.isTie = true
                break
            }
            // Solo miramos las últimas líneas con contenido.
            if line.contains("'s Turn") { break }
        }
        return summary
    }
}

private extension String {
    func captures(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: self).map { String(self[$0]) } }
    }

    func capture(_ pattern: String) -> String? {
        captures(pattern)?.first
    }
}
