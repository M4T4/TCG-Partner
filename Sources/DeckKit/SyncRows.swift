import Foundation

/// Fechas como las manda y las espera Supabase: ISO 8601 con fracciones de segundo
/// («2026-11-09T18:34:05.123456+00:00»). Al leer también acepta fechas sin fracciones.
public enum SyncDates {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(_ date: Date) -> String {
        fractional.string(from: date)
    }

    /// Postgres manda hasta 6 decimales; `ISO8601DateFormatter` solo entiende 3, así que se recortan.
    public static func date(_ text: String) -> Date? {
        if let date = whole.date(from: text) { return date }
        let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return fractional.date(from: trimmed)
    }

    /// La fecha que se pone a los elementos anteriores a la sincronización (sin `updatedAt`):
    /// cualquier cambio hecho en otro equipo les gana.
    public static let legacy = Date(timeIntervalSince1970: 0)
}

/// Relación entre una propiedad del modelo Swift y su columna en Supabase («deckID» ↔ «deck_id»).
public struct SyncColumn: Hashable, Sendable {
    public var key: String
    public var column: String

    public init(_ key: String, _ column: String) {
        self.key = key
        self.column = column
    }

    /// Para propiedades que se llaman igual en Swift y en la base de datos («name», «notes»).
    public init(_ name: String) {
        self.init(name, name)
    }
}

/// Una fila leída de Supabase: el elemento y sus datos de sincronización.
public struct RemoteRow<Item> {
    public var item: Item
    /// Si la fila está borrada en la nube.
    public var deletedAt: Date?
    public var serverUpdatedAt: Date?

    public init(item: Item, deletedAt: Date? = nil, serverUpdatedAt: Date? = nil) {
        self.item = item
        self.deletedAt = deletedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}

public enum SyncRowError: Error, LocalizedError {
    case notAnArray
    case missingColumn(String)

    public var errorDescription: String? {
        switch self {
        case .notAnArray: "La respuesta de la nube no es una lista de filas."
        case .missingColumn(let column): "Falta la columna «\(column)» en la respuesta de la nube."
        }
    }
}

/// Convierte modelos a filas de Supabase y al revés, con una lista explícita de columnas.
public struct SyncRowCoder: Sendable {
    public var columns: [SyncColumn]

    public init(columns: [SyncColumn]) {
        self.columns = columns
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncDates.string(date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = SyncDates.date(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha no válida: \(text)")
            }
            return date
        }
        return decoder
    }

    /// Filas listas para un upsert: todas las columnas aparecen, con `null` si el valor es `nil`,
    /// para que borrar un campo en la app también lo borre en la nube. `deleted_at` va siempre en `null`
    /// (guardar un elemento lo «revive» si su cambio es más reciente que el borrado).
    public func rows<Item: Encodable>(_ items: [Item]) throws -> Data {
        let encoded = try Self.encoder().encode(items)
        guard let objects = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] else {
            throw SyncRowError.notAnArray
        }
        let rows: [[String: Any]] = objects.map { object in
            var row: [String: Any] = ["deleted_at": NSNull()]
            for column in columns {
                row[column.column] = object[column.key] ?? NSNull()
            }
            if row["updated_at"] is NSNull { row["updated_at"] = SyncDates.string(SyncDates.legacy) }
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    }

    /// Lee la respuesta de un `select` de Supabase.
    public func decode<Item: Decodable>(_ type: Item.Type, from data: Data) throws -> [RemoteRow<Item>] {
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SyncRowError.notAnArray
        }
        let decoder = Self.decoder()
        return try objects.map { object in
            var fields: [String: Any] = [:]
            for column in columns {
                guard let value = object[column.column] else { throw SyncRowError.missingColumn(column.column) }
                if !(value is NSNull) { fields[column.key] = value }
            }
            let item = try decoder.decode(Item.self, from: JSONSerialization.data(withJSONObject: fields))
            return RemoteRow(item: item,
                             deletedAt: (object["deleted_at"] as? String).flatMap(SyncDates.date),
                             serverUpdatedAt: (object["server_updated_at"] as? String).flatMap(SyncDates.date))
        }
    }
}

/// Qué cambió al aplicar filas de la nube.
public struct SyncMergeResult: Equatable, Sendable {
    /// Elementos añadidos o reemplazados.
    public var upserted: [UUID] = []
    /// Elementos quitados porque se borraron en otro equipo.
    public var removed: [UUID] = []

    public var changed: Bool { !upserted.isEmpty || !removed.isEmpty }

    public init(upserted: [UUID] = [], removed: [UUID] = []) {
        self.upserted = upserted
        self.removed = removed
    }
}

public enum SyncMerge {
    /// Aplica filas de la nube a la lista local. Gana el `updatedAt` más reciente; en caso de empate,
    /// la nube. Un borrado en la nube solo quita el elemento si no se cambió aquí después.
    /// `pending` son los ids borrados aquí que aún no se suben: no se reviven.
    public static func apply<Item: Syncable>(_ rows: [RemoteRow<Item>], to local: inout [Item],
                                             pending: Set<UUID> = []) -> SyncMergeResult {
        var result = SyncMergeResult()
        for row in rows where !pending.contains(row.item.id) {
            let index = local.firstIndex { $0.id == row.item.id }
            let localStamp = index.map { local[$0].updatedAt ?? SyncDates.legacy }
            if let deletedAt = row.deletedAt {
                if let index, let localStamp, localStamp <= deletedAt {
                    local.remove(at: index)
                    result.removed.append(row.item.id)
                }
                continue
            }
            let remoteStamp = row.item.updatedAt ?? SyncDates.legacy
            if let index, let localStamp {
                guard remoteStamp >= localStamp, local[index] != row.item else { continue }
                local[index] = row.item
            } else {
                local.append(row.item)
            }
            result.upserted.append(row.item.id)
        }
        return result
    }

    /// Elementos que hay que subir: todos la primera vez (`pushedAt == nil`) y luego los que cambiaron después.
    public static func pending<Item: Syncable>(_ items: [Item], since pushedAt: Date?) -> [Item] {
        guard let pushedAt else { return items }
        return items.filter { ($0.updatedAt ?? SyncDates.legacy) > pushedAt }
    }
}

public extension MatchRecord {
    /// Columnas de la tabla `matches`.
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("date"), .init("deckID", "deck_id"), .init("result"), .init("opponent"),
        .init("opponentArchetype", "opponent_archetype"), .init("eventID", "event_id"), .init("notes"),
        .init("kind"), .init("battleLog", "battle_log"), .init("wentFirst", "went_first"), .init("turns"),
        .init("myPrizes", "my_prizes"), .init("opponentPrizes", "opponent_prizes"), .init("round"),
        .init("updatedAt", "updated_at"),
    ]
}

public extension JournalEntry {
    /// Columnas de la tabla `journal_entries`.
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("archetypeID", "archetype_id"), .init("kind"), .init("title"), .init("body"),
        .init("opponent"), .init("matchID", "match_id"), .init("pinned"), .init("created"), .init("modified"),
        .init("updatedAt", "updated_at"),
    ]
}
