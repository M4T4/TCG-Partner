import Foundation

/// Las tres secciones de una lista de Pokémon TCG.
public enum DeckSection: String, CaseIterable, Codable, Sendable {
    case pokemon, trainer, energy

    public var title: String {
        switch self {
        case .pokemon: "Pokémon"
        case .trainer: "Entrenador"
        case .energy: "Energía"
        }
    }

    /// Cabecera tal como la escriben Limitless y PTCG Live.
    public var exportHeader: String {
        switch self {
        case .pokemon: "Pokémon"
        case .trainer: "Trainer"
        case .energy: "Energy"
        }
    }
}

/// Una línea de la lista: «4 Dreepy TWM 128».
public struct CardEntry: Hashable, Sendable, Identifiable {
    public var count: Int
    public var name: String
    /// Código de expansión de PTCG Live (TWM, SVI, SVE…). `nil` si la línea solo traía el nombre.
    public var setCode: String?
    /// Número de colección tal como venía (128, 5, TG03…).
    public var number: String?
    public var section: DeckSection

    public init(count: Int, name: String, setCode: String? = nil, number: String? = nil, section: DeckSection) {
        self.count = count
        self.name = name
        self.setCode = setCode
        self.number = number
        self.section = section
    }

    public var id: String { "\(section.rawValue)|\(name)|\(setCode ?? "")|\(number ?? "")" }

    /// Clave estable de la carta impresa («TWM-128»), o el nombre si no hay set y número.
    public var cardKey: String {
        if let setCode, let number { return "\(setCode)-\(number)" }
        return "name-\(searchName)"
    }

    /// Número con tres dígitos, como lo usa el CDN de Limitless («5» → «005»; «TG03» se queda igual).
    public var paddedNumber: String? {
        guard let number else { return nil }
        guard let value = Int(number) else { return number }
        return String(format: "%03d", value)
    }

    /// Nombre para buscar en APIs: «Basic {P} Energy» → «Psychic Energy».
    public var searchName: String {
        var name = printName
        if name.hasPrefix("Basic "), name.hasSuffix(" Energy") { name.removeFirst("Basic ".count) }
        return name
    }

    /// Nombre para la hoja impresa, sin símbolos de tipo: «Basic {P} Energy» → «Basic Psychic Energy».
    public var printName: String {
        var name = name
        for (symbol, type) in Self.energySymbols {
            name = name.replacingOccurrences(of: "{\(symbol)}", with: type)
        }
        return name
    }

    private static let energySymbols = [
        ("G", "Grass"), ("R", "Fire"), ("W", "Water"), ("L", "Lightning"),
        ("P", "Psychic"), ("F", "Fighting"), ("D", "Darkness"), ("M", "Metal"),
    ]

    /// La línea en formato Limitless.
    public var exportLine: String {
        [String(count), name, setCode, number].compactMap { $0 }.joined(separator: " ")
    }
}

public struct ParsedDeck: Sendable {
    public var entries: [CardEntry]
    /// Líneas con contenido que no parecían ni cabecera ni carta.
    public var unparsedLines: [String]

    public init(entries: [CardEntry] = [], unparsedLines: [String] = []) {
        self.entries = entries
        self.unparsedLines = unparsedLines
    }

    public var totalCount: Int { entries.reduce(0) { $0 + $1.count } }
    public var isStandardSize: Bool { totalCount == 60 }
    public var isEmpty: Bool { entries.isEmpty }

    public func entries(in section: DeckSection) -> [CardEntry] {
        entries.filter { $0.section == section }
    }

    public func count(in section: DeckSection) -> Int {
        entries(in: section).reduce(0) { $0 + $1.count }
    }

    /// «60 cartas · 17 Pokémon · 35 Entrenador · 8 Energía».
    public var summary: String {
        let parts = DeckSection.allCases.map { "\(count(in: $0)) \($0.title)" }
        return ([totalCount == 1 ? "1 carta" : "\(totalCount) cartas"] + parts).joined(separator: " · ")
    }

    /// Nombre propuesto para un mazo nuevo: el primer Pokémon «ex» o, si no hay, el primer Pokémon.
    public var suggestedName: String {
        let pokemon = entries(in: .pokemon)
        let star = pokemon.first { $0.name.hasSuffix(" ex") || $0.name.contains(" ex ") } ?? pokemon.first
        return star?.name ?? "Mazo nuevo"
    }

    /// La lista en el formato de Limitless / PTCG Live, lista para pegar en el juego.
    public func export() -> String {
        var blocks: [String] = []
        for section in DeckSection.allCases {
            let cards = entries(in: section)
            guard !cards.isEmpty else { continue }
            blocks.append((["\(section.exportHeader): \(count(in: section))"] + cards.map(\.exportLine))
                .joined(separator: "\n"))
        }
        blocks.append("Total Cards: \(totalCount)")
        return blocks.joined(separator: "\n\n")
    }
}

/// Lee listas exportadas desde Limitless o PTCG Live (formato nuevo y el antiguo con «##» y «*»).
public enum DeckParser {
    // «Pokémon: 17», «##Trainer Cards - 35», «Energía», «Entrenadores: 30»…
    private static let header = try! NSRegularExpression(
        pattern: #"^#*\s*(pok[eé]mon|trainers?|trainer cards|entrenador(?:es)?|energy|energ[ií]as?)\s*(?:[:\-–]\s*\d*)?\s*$"#,
        options: .caseInsensitive)
    // «4 Dreepy TWM 128», «* 1 Pikachu with Grey Felt Hat SVP 85», «1 Charizard VSTAR BRS TG03».
    private static let fullLine = try! NSRegularExpression(
        pattern: #"^\*?\s*(\d+)\s+(.+?)\s+([A-Z][A-Z0-9-]{1,5})\s+([A-Za-z]{0,3}\d+[A-Za-z]?)$"#)
    // «4 Arven»: solo cantidad y nombre.
    private static let nameOnlyLine = try! NSRegularExpression(pattern: #"^\*?\s*(\d+)\s+(\S.*)$"#)

    public static func parse(_ text: String) -> ParsedDeck {
        var deck = ParsedDeck()
        var section: DeckSection?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("***") || line.lowercased().hasPrefix("total") { continue }
            if let match = header.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                section = Self.section(named: line.capture(match, 1))
                continue
            }
            if let match = fullLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let count = Int(line.capture(match, 1)), count > 0 {
                let name = line.capture(match, 2)
                deck.entries.append(CardEntry(count: count, name: name, setCode: line.capture(match, 3),
                                              number: line.capture(match, 4),
                                              section: section ?? guessSection(name)))
            } else if let match = nameOnlyLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let count = Int(line.capture(match, 1)), count > 0 {
                let name = line.capture(match, 2)
                deck.entries.append(CardEntry(count: count, name: name, section: section ?? guessSection(name)))
            } else {
                deck.unparsedLines.append(line)
            }
        }
        return deck
    }

    private static func section(named raw: String) -> DeckSection {
        let name = raw.lowercased()
        if name.hasPrefix("pok") { return .pokemon }
        if name.hasPrefix("energ") { return .energy }
        return .trainer
    }

    /// Para líneas que llegan antes de cualquier cabecera.
    private static func guessSection(_ name: String) -> DeckSection {
        name.hasSuffix("Energy") ? .energy : .pokemon
    }
}

private extension String {
    func capture(_ match: NSTextCheckingResult, _ index: Int) -> String {
        Range(match.range(at: index), in: self).map { String(self[$0]) } ?? ""
    }
}
