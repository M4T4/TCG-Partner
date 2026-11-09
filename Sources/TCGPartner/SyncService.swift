import AppKit
import Combine
import DeckKit
import Foundation
import Supabase

// MARK: - Columnas de cada tabla

extension Deck {
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("name"), .init("list"), .init("notes"), .init("folder"),
        .init("archetypeID", "archetype_id"), .init("status"), .init("icons"), .init("created"), .init("modified"),
        .init("updatedAt", "updated_at"),
    ]
}

extension FolderRow {
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("name"), .init("archetypeID", "archetype_id"), .init("icons"), .init("updatedAt", "updated_at"),
    ]
}

extension Archetype {
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("name"), .init("color"), .init("icons"), .init("notes"), .init("updatedAt", "updated_at"),
    ]
}

extension TournamentEvent {
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("name"), .init("kind"), .init("startDate", "start_date"), .init("endDate", "end_date"),
        .init("location"), .init("link"), .init("cost"), .init("currency"), .init("format"),
        .init("plannedDeckID", "planned_deck_id"), .init("registered"), .init("placement"), .init("players"),
        .init("notes"), .init("updatedAt", "updated_at"),
    ]
}

extension Player {
    static let syncColumns: [SyncColumn] = [
        .init("id"), .init("name"), .init("playerID", "player_id"), .init("birthDate", "birth_date"),
        .init("updatedAt", "updated_at"),
    ]
}

// MARK: - Estado guardado

/// Hasta dónde se sincronizó cada tabla, por usuario (`sync-state.json`).
private struct SyncState: Codable {
    struct Table: Codable {
        /// El `server_updated_at` más reciente que se bajó.
        var pulledThrough: Date?
        /// Cuándo se subieron los cambios locales por última vez (reloj de este equipo).
        var pushedAt: Date?
    }

    var userID: UUID
    var tables: [String: Table] = [:]
    var lastSync: Date?
}

// MARK: - Servicio

/// Sincroniza los datos locales con Supabase: baja lo que cambió en la nube, sube los borrados y
/// luego los cambios de este equipo. Los JSON locales siguen siendo la copia de trabajo, así que
/// la app funciona igual sin conexión.
@MainActor
final class SyncService: ObservableObject {
    struct Stores {
        let decks: DeckStore
        let players: PlayerStore
        let archetypes: ArchetypeStore
        let matches: MatchStore
        let events: EventStore
        let journal: JournalStore
    }

    @Published private(set) var email: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published var errorMessage: String?

    let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey,
        options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
    )

    private var stores: Stores?
    private var cancellables = Set<AnyCancellable>()
    /// Mientras se aplican cambios de la nube, los cambios en los stores no piden otra sincronización.
    private var isApplying = false
    private var resyncRequested = false
    private let stateFile = DeckStore.supportFolder.appendingPathComponent("sync-state.json")
    private static let pageSize = 1000
    private static let pushBatch = 500
    /// Cada cuánto se sincroniza aunque no haya cambios aquí (para traer los de otros equipos).
    private static let interval: TimeInterval = 120

    init() {
        email = client.auth.currentUser?.email
        lastSync = loadState(for: client.auth.currentUser?.id)?.lastSync
        Task { [weak self, client] in
            for await (_, session) in client.auth.authStateChanges {
                self?.email = session?.user.email
            }
        }
    }

    /// Conecta los stores y empieza a sincronizar: al abrir, al volver a la app, cada 2 minutos
    /// y unos segundos después de cada cambio.
    func attach(_ stores: Stores) {
        guard self.stores == nil else { return }
        self.stores = stores
        let changes: [AnyPublisher<Void, Never>] = [
            stores.decks.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            stores.players.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            stores.archetypes.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            stores.matches.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            stores.events.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            stores.journal.objectWillChange.map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .filter { [weak self] in self?.isApplying == false }
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { [weak self] in self?.requestSync() }
            .store(in: &cancellables)
        Timer.publish(every: Self.interval, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.requestSync() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.requestSync() }
            .store(in: &cancellables)
        requestSync()
    }

    // MARK: Sesión

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            self.email = session.user.email
            lastSync = loadState(for: session.user.id)?.lastSync
            requestSync()
        } catch {
            errorMessage = "No se pudo iniciar sesión: \(error.localizedDescription)"
        }
    }

    /// Cierra la sesión. Los datos de este equipo se quedan como están.
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            // Sin conexión no se puede avisar al servidor, pero la sesión local se borra igual.
        }
        email = nil
        lastSync = nil
    }

    // MARK: Sincronizar

    func requestSync() {
        guard email != nil, stores != nil else { return }
        guard !isSyncing else {
            resyncRequested = true
            return
        }
        Task { await sync() }
    }

    private func sync() async {
        guard let stores else { return }
        isSyncing = true
        defer {
            isSyncing = false
            if resyncRequested {
                resyncRequested = false
                requestSync()
            }
        }
        do {
            let session = try await client.auth.session
            var state = loadState(for: session.user.id) ?? SyncState(userID: session.user.id)
            stores.decks.flush()

            // Las carpetas antes que los mazos, para que existan cuando lleguen sus mazos.
            try await syncTable("folders", FolderRow.syncColumns, state: &state,
                                items: { stores.decks.folderRows },
                                apply: { stores.decks.applyRemoteFolders($0, pending: $1) })
            try await syncTable("decks", Deck.syncColumns, state: &state,
                                items: { stores.decks.decks },
                                apply: { stores.decks.applyRemote($0, pending: $1) })
            try await syncTable("archetypes", Archetype.syncColumns, state: &state,
                                items: { stores.archetypes.items },
                                apply: { stores.archetypes.applyRemote($0, pending: $1) })
            try await syncTable("matches", MatchRecord.syncColumns, state: &state,
                                items: { stores.matches.items },
                                apply: { stores.matches.applyRemote($0, pending: $1) })
            try await syncTable("events", TournamentEvent.syncColumns, state: &state,
                                items: { stores.events.items },
                                apply: { stores.events.applyRemote($0, pending: $1) })
            try await syncTable("journal_entries", JournalEntry.syncColumns, state: &state,
                                items: { stores.journal.items },
                                apply: { stores.journal.applyRemote($0, pending: $1) })
            try await syncTable("players", Player.syncColumns, state: &state,
                                items: { stores.players.players },
                                apply: { stores.players.applyRemote($0, pending: $1) })

            state.lastSync = Date()
            saveState(state)
            lastSync = state.lastSync
            errorMessage = nil
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func syncTable<Item: Syncable & Codable>(
        _ table: String,
        _ columns: [SyncColumn],
        state: inout SyncState,
        items: () -> [Item],
        apply: ([RemoteRow<Item>], Set<UUID>) -> Void
    ) async throws {
        let coder = SyncRowCoder(columns: columns)
        var tableState = state.tables[table] ?? SyncState.Table()
        let deletions = DeletionLogStore.shared

        // 1. Bajar lo que cambió en la nube. Se repiten 5 s por si otra escritura terminó justo después.
        let since = tableState.pulledThrough?.addingTimeInterval(-5)
        var rows: [RemoteRow<Item>] = []
        var offset = 0
        while true {
            var query = client.from(table).select()
            if let since { query = query.gt("server_updated_at", value: SyncDates.string(since)) }
            let response = try await query.order("server_updated_at")
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
            let page = try coder.decode(Item.self, from: response.data)
            rows += page
            if page.count < Self.pageSize { break }
            offset += Self.pageSize
        }
        if !rows.isEmpty {
            let pending = Set(deletions.log.tombstones(in: table).map(\.id))
            isApplying = true
            apply(rows, pending)
            isApplying = false
            if let newest = rows.compactMap(\.serverUpdatedAt).max() {
                tableState.pulledThrough = max(tableState.pulledThrough ?? newest, newest)
            }
        }

        // 2. Subir los borrados de este equipo.
        for tombstone in deletions.log.tombstones(in: table) {
            let stamp = AnyJSON.string(SyncDates.string(tombstone.deletedAt))
            try await client.from(table)
                .update(["deleted_at": stamp, "updated_at": stamp], returning: .minimal)
                .eq("id", value: tombstone.id)
                .execute()
            deletions.remove([tombstone])
        }

        // 3. Subir los cambios de este equipo.
        let pushStart = Date()
        let pending = SyncMerge.pending(items(), since: tableState.pushedAt)
        for start in stride(from: 0, to: pending.count, by: Self.pushBatch) {
            let batch = Array(pending[start..<min(start + Self.pushBatch, pending.count)])
            let objects = try JSONSerialization.jsonObject(with: coder.rows(batch)) as? [Any] ?? []
            let body = objects.compactMap { Self.anyJSON($0).objectValue }
            try await client.from(table).upsert(body, onConflict: "id", returning: .minimal).execute()
        }
        // Un segundo de margen: en disco las fechas se guardan sin fracciones de segundo.
        tableState.pushedAt = pushStart.addingTimeInterval(-1)
        state.tables[table] = tableState
    }

    // MARK: Utilidades

    /// Convierte lo que da JSONSerialization a AnyJSON sin confundir booleanos con números.
    private static func anyJSON(_ value: Any) -> AnyJSON {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .integer(number.intValue)
        case let text as String:
            return .string(text)
        case let array as [Any]:
            return .array(array.map(anyJSON))
        case let object as [String: Any]:
            return .object(object.mapValues(anyJSON))
        default:
            return .null
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            return "Sin conexión. Los cambios se subirán cuando vuelva."
        }
        if let error = error as? PostgrestError { return "Error de la nube: \(error.message)" }
        return "No se pudo sincronizar: \(error.localizedDescription)"
    }

    private func loadState(for user: UUID?) -> SyncState? {
        guard let user, let data = try? Data(contentsOf: stateFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return SyncDates.date(text) ?? .distantPast
        }
        guard let state = try? decoder.decode(SyncState.self, from: data), state.userID == user else { return nil }
        return state
    }

    private func saveState(_ state: SyncState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncDates.string(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(state).write(to: stateFile, options: .atomic)
    }
}
