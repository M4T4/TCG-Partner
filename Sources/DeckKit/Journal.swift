import Foundation

/// Tipo de anotación del journal de un arquetipo.
public enum JournalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Lo que aprendiste en una partida («contra Gardevoir, guardar Counter Catcher»).
    case lesson
    /// Una guía: plan de juego, matchups, mulligans, cómo jugar el mazo.
    case guide
    /// Nota libre.
    case note

    public var id: Self { self }

    public var title: String {
        switch self {
        case .lesson: "Aprendizaje"
        case .guide: "Guía"
        case .note: "Nota"
        }
    }

    public var plural: String {
        switch self {
        case .lesson: "Aprendizajes"
        case .guide: "Guías"
        case .note: "Notas"
        }
    }
}

/// Una anotación del journal. Pertenece a un arquetipo y puede ligarse a un mazo rival y a una partida.
public struct JournalEntry: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var archetypeID: UUID
    public var kind: JournalKind
    public var title: String
    public var body: String
    /// Mazo rival del que habla («Gardevoir ex»); vacío si es general.
    public var opponent: String
    /// Partida de la que salió el aprendizaje.
    public var matchID: UUID?
    /// Fijada: aparece arriba y en «Para recordar» de la página del arquetipo.
    public var pinned: Bool
    public var created: Date
    public var modified: Date
    /// Última modificación en este equipo, para sincronizar. A diferencia de `modified`, cambia con
    /// cualquier cambio (fijar, mover de arquetipo…), no solo al editar el texto.
    public var updatedAt: Date?

    public init(archetypeID: UUID, kind: JournalKind = .note, title: String = "", body: String = "",
                opponent: String = "", matchID: UUID? = nil, pinned: Bool = false, date: Date = Date()) {
        self.archetypeID = archetypeID
        self.kind = kind
        self.title = title
        self.body = body
        self.opponent = opponent
        self.matchID = matchID
        self.pinned = pinned
        created = date
        modified = date
    }

    /// El título o, si no tiene, la primera línea del texto.
    public var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let firstLine = body.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstLine.map { String($0.prefix(80)) } ?? "Sin título"
    }

    /// Un resumen del texto en una línea (sin repetir la línea usada como título).
    public var preview: String {
        var lines = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lines.isEmpty { lines.removeFirst() }
        return String(lines.joined(separator: " ").prefix(160))
    }

    public var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filtra por tipo y por texto (título, texto y rival, sin importar mayúsculas ni acentos).
    /// Orden: fijadas primero, luego la última modificada.
    public static func filter(_ entries: [JournalEntry], kind: JournalKind? = nil, query: String = "") -> [JournalEntry] {
        let words = query.split(separator: " ").map { fold(String($0)) }
        return entries
            .filter { kind == nil || $0.kind == kind }
            .filter { entry in
                guard !words.isEmpty else { return true }
                let haystack = fold("\(entry.title) \(entry.body) \(entry.opponent)")
                return words.allSatisfy(haystack.contains)
            }
            .sorted { ($0.pinned ? 1 : 0, $0.modified) > ($1.pinned ? 1 : 0, $1.modified) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
