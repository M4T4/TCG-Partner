import Foundation

/// Un elemento que se sincroniza con la nube. `updatedAt` es la última vez que cambió en este equipo;
/// si dos equipos cambian el mismo elemento, gana el `updatedAt` más reciente.
/// Es opcional porque los JSON anteriores a la sincronización no lo tienen.
public protocol Syncable: Identifiable, Hashable where ID == UUID {
    var updatedAt: Date? { get set }
}

public extension Syncable {
    /// El mismo elemento sin la marca de tiempo, para comparar solo el contenido.
    var withoutTimestamp: Self {
        var copy = self
        copy.updatedAt = nil
        return copy
    }
}

public extension Array where Element: Syncable {
    /// Añade el elemento o reemplaza el que tenga su mismo id, poniéndole `updatedAt = now`.
    /// Si el contenido no cambió (sin contar la marca de tiempo) no toca nada y devuelve `false`.
    @discardableResult
    mutating func upsertStamped(_ item: Element, now: Date = Date()) -> Bool {
        var item = item
        if let index = firstIndex(where: { $0.id == item.id }) {
            guard self[index].withoutTimestamp != item.withoutTimestamp else { return false }
            item.updatedAt = now
            self[index] = item
        } else {
            item.updatedAt = now
            append(item)
        }
        return true
    }
}

/// Registro de un elemento borrado, para que el borrado llegue también a los otros equipos.
public struct Tombstone: Codable, Hashable, Sendable {
    /// Tabla de la nube a la que pertenece («decks», «matches»…).
    public var table: String
    public var id: UUID
    public var deletedAt: Date

    public init(table: String, id: UUID, deletedAt: Date = Date()) {
        self.table = table
        self.id = id
        self.deletedAt = deletedAt
    }
}

/// Los borrados que aún hay que contar a la nube. Se guarda junto a los datos (`deleted.json`).
public struct DeletionLog: Codable, Hashable, Sendable {
    public private(set) var tombstones: [Tombstone]

    public init(tombstones: [Tombstone] = []) {
        self.tombstones = tombstones
    }

    /// Anota el borrado. Si ya estaba anotado, conserva la fecha más reciente.
    public mutating func record(table: String, id: UUID, at date: Date = Date()) {
        if let index = tombstones.firstIndex(where: { $0.table == table && $0.id == id }) {
            tombstones[index].deletedAt = max(tombstones[index].deletedAt, date)
        } else {
            tombstones.append(Tombstone(table: table, id: id, deletedAt: date))
        }
    }

    public func tombstones(in table: String) -> [Tombstone] {
        tombstones.filter { $0.table == table }
    }

    /// Olvida los borrados que la nube ya recibió.
    public mutating func remove(_ done: [Tombstone]) {
        let done = Set(done.map { "\($0.table)/\($0.id)" })
        tombstones.removeAll { done.contains("\($0.table)/\($0.id)") }
    }
}

extension MatchRecord: Syncable {}
extension JournalEntry: Syncable {}
