import DeckKit
import Foundation

/// Un mazo guardado. El texto de la lista es la fuente de verdad: se vuelve a leer con `DeckParser`.
struct Deck: Syncable, Codable {
    var id: UUID
    var name: String
    var list: String
    var notes: String
    /// Carpeta de la barra lateral; `nil` = suelto. Los JSON antiguos no lo tienen y se leen como `nil`.
    var folder: String?
    /// Arquetipo de un mazo que no está en carpeta (si está en carpeta, manda el arquetipo de la carpeta).
    var archetypeID: UUID?
    var status: DeckStatus?
    /// Iconos propios del mazo (1 o 2 Pokémon). `nil` = los de su carpeta o arquetipo.
    var icons: [String]?
    var created: Date
    /// Última edición de la lista, el nombre o las notas (la que se muestra en la app).
    var modified: Date
    /// Último cambio de cualquier tipo, incluso mover o cambiar iconos, para sincronizar.
    var updatedAt: Date?

    var parsed: ParsedDeck { DeckParser.parse(list) }
    var currentStatus: DeckStatus { status ?? .testing }
}

/// Dónde está un mazo en la barra lateral.
enum DeckLocation: Hashable {
    /// Sin carpeta ni arquetipo.
    case loose
    case folder(String)
    /// Directamente dentro de un arquetipo, sin carpeta.
    case archetype(UUID)
}

/// Una carpeta tal como se guarda en la nube (en la app se identifican por nombre).
struct FolderRow: Syncable, Codable {
    var id: UUID
    var name: String
    var archetypeID: UUID?
    var icons: [String]?
    var updatedAt: Date?
}

/// Formato de folders.json: las carpetas y, opcionalmente, el arquetipo de cada una.
private struct FoldersFile: Codable {
    var folders: [String]
    var archetypes: [String: UUID]
    /// Iconos propios de cada carpeta (opcional: los archivos anteriores no lo tienen).
    var icons: [String: [String]]?
    /// Id estable de cada carpeta en la nube, que se conserva al renombrarla (opcional, como `icons`).
    var ids: [String: UUID]?
    /// Último cambio de cada carpeta, para sincronizar.
    var updated: [String: Date]?
}

/// Guarda cada mazo como un JSON en `~/Library/Application Support/TCGPartner/Decks`.
@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var decks: [Deck] = []
    /// Carpetas de la barra lateral, ordenadas por nombre (se guardan aparte para conservar las vacías).
    @Published private(set) var folders: [String] = []
    /// Arquetipo de cada carpeta (las que no aparecen no tienen arquetipo).
    @Published private(set) var folderArchetypes: [String: UUID] = [:]
    /// Iconos propios de cada carpeta (las que no aparecen usan los de su arquetipo).
    @Published private(set) var folderIcons: [String: [String]] = [:]
    /// Id de cada carpeta en la nube y su último cambio (no se muestran, solo se sincronizan).
    private(set) var folderIDs: [String: UUID] = [:]
    private(set) var folderUpdated: [String: Date] = [:]
    @Published var selectedID: Deck.ID?
    @Published var errorMessage: String?

    let folder: URL
    private var unsaved: Set<Deck.ID> = []
    private var saveTask: Task<Void, Never>?

    nonisolated static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGPartner", isDirectory: true)
    }

    private var foldersFile: URL { folder.deletingLastPathComponent().appendingPathComponent("folders.json") }

    init(folder: URL = DeckStore.supportFolder.appendingPathComponent("Decks", isDirectory: true)) {
        self.folder = folder
        load()
    }

    /// Ubicación donde se crea un mazo nuevo: la del mazo seleccionado.
    var currentLocation: DeckLocation { selectedDeck.map(location) ?? .loose }

    func decks(in folderName: String?) -> [Deck] {
        decks.filter { $0.folder == folderName }
    }

    func location(of deck: Deck) -> DeckLocation {
        if let folder = deck.folder { return .folder(folder) }
        if let archetype = deck.archetypeID { return .archetype(archetype) }
        return .loose
    }

    func decks(at location: DeckLocation) -> [Deck] {
        decks.filter { self.location(of: $0) == location }
    }

    /// Arquetipo efectivo del mazo: el de su carpeta o, si está suelto, el suyo propio.
    func archetypeID(of deck: Deck) -> UUID? {
        if let folder = deck.folder { return folderArchetypes[folder] }
        return deck.archetypeID
    }

    /// Carpetas de un arquetipo (`nil` = carpetas sin arquetipo).
    func folders(of archetype: UUID?) -> [String] {
        folders.filter { folderArchetypes[$0] == archetype }
    }

    /// Todos los mazos de un arquetipo, estén en carpeta o no.
    func decks(ofArchetype archetype: UUID?) -> [Deck] {
        decks.filter { archetypeID(of: $0) == archetype }
    }

    func deck(_ id: Deck.ID) -> Deck? {
        decks.first { $0.id == id }
    }

    var selectedDeck: Deck? { selectedID.flatMap(deck) }

    func load() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decks = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                .filter { $0.pathExtension == "json" }
                .compactMap { try? decoder.decode(Deck.self, from: Data(contentsOf: $0)) }
            sort()
            // folders.json era una lista de nombres; ahora también guarda el arquetipo de cada carpeta.
            let data = try? Data(contentsOf: foldersFile)
            let file = data.flatMap { try? decoder.decode(FoldersFile.self, from: $0) }
                ?? FoldersFile(folders: data.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [], archetypes: [:], icons: nil)
            // También las carpetas que usan los mazos, por si folders.json se perdió.
            folders = Self.sortedNames(Set(file.folders + decks.compactMap(\.folder)))
            folderArchetypes = file.archetypes.filter { folders.contains($0.key) }
            folderIcons = (file.icons ?? [:]).filter { folders.contains($0.key) }
            folderIDs = (file.ids ?? [:]).filter { folders.contains($0.key) }
            folderUpdated = (file.updated ?? [:]).filter { folders.contains($0.key) }
            // Las carpetas de antes de la sincronización reciben un id una sola vez y se guarda,
            // para que no cambie en cada arranque (si cambiara, se duplicarían en la nube).
            let missing = folders.filter { folderIDs[$0] == nil }
            if !missing.isEmpty {
                for name in missing { folderIDs[name] = UUID() }
                saveFolders()
            }
            if selectedID == nil || deck(selectedID!) == nil { selectedID = decks.first?.id }
        } catch {
            errorMessage = "No se pudo abrir la carpeta de mazos: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func create(name: String, list: String, at location: DeckLocation = .loose) -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        var deck = Deck(id: UUID(), name: trimmed.isEmpty ? DeckParser.parse(list).suggestedName : trimmed,
                        list: list, notes: "", status: .testing, created: now, modified: now, updatedAt: now)
        switch location {
        case .loose: break
        case .folder(let name): deck.folder = folders.contains(name) ? name : nil
        case .archetype(let id): deck.archetypeID = id
        }
        decks.insert(deck, at: 0)
        write(deck)
        selectedID = deck.id
        return deck
    }

    func update(_ id: Deck.ID, _ change: (inout Deck) -> Void) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        var deck = decks[index]
        change(&deck)
        guard deck != decks[index] else { return }
        deck.modified = Date()
        decks[index] = deck
        unsaved.insert(id)
        scheduleSave()
    }

    func duplicate(_ id: Deck.ID) {
        guard let original = deck(id) else { return }
        let copy = create(name: "\(original.name) (copia)", list: original.list, at: location(of: original))
        update(copy.id) {
            $0.notes = original.notes
            $0.status = original.status
        }
    }

    func delete(_ id: Deck.ID) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        unsaved.remove(id)
        do {
            try PlatformFiles.discard(file(for: id))
        } catch {
            errorMessage = "No se pudo eliminar el mazo: \(error.localizedDescription)"
            return
        }
        decks.remove(at: index)
        DeletionLogStore.shared.record(table: "decks", id: id)
        if selectedID == id {
            selectedID = decks.isEmpty ? nil : decks[min(index, decks.count - 1)].id
        }
    }

    // MARK: - Carpetas

    /// Mueve el mazo sin cambiar su fecha de modificación.
    func move(_ id: Deck.ID, to destination: DeckLocation) {
        guard let index = decks.firstIndex(where: { $0.id == id }), location(of: decks[index]) != destination else { return }
        if case .folder(let name) = destination, !folders.contains(name) { return }
        switch destination {
        case .loose:
            decks[index].folder = nil
            decks[index].archetypeID = nil
        case .folder(let name):
            decks[index].folder = name
            decks[index].archetypeID = nil
        case .archetype(let archetype):
            decks[index].folder = nil
            decks[index].archetypeID = archetype
        }
        unsaved.insert(id)
        flush()
    }

    /// Relaciona una carpeta con un arquetipo (`nil` = sin arquetipo).
    func setArchetype(_ archetype: UUID?, forFolder name: String) {
        guard folders.contains(name), folderArchetypes[name] != archetype else { return }
        folderArchetypes[name] = archetype
        touchFolder(name)
        saveFolders()
    }

    // MARK: - Iconos

    /// Iconos propios de una carpeta (vacío = usar los de su arquetipo).
    func setIcons(_ icons: [String], forFolder name: String) {
        guard folders.contains(name) else { return }
        folderIcons[name] = icons.isEmpty ? nil : icons
        touchFolder(name)
        saveFolders()
    }

    /// Iconos propios de un mazo (vacío = heredar). No cambia su fecha de modificación.
    func setIcons(_ icons: [String], forDeck id: Deck.ID) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[index].icons = icons.isEmpty ? nil : icons
        unsaved.insert(id)
        flush()
    }

    /// Iconos heredados por un mazo si no tiene propios: los de su carpeta o los de su arquetipo.
    func inheritedIcons(for deck: Deck, archetypes: ArchetypeStore) -> [String]? {
        if let folder = deck.folder, let icons = folderIcons[folder] { return icons }
        return archetypes.item(archetypeID(of: deck))?.iconNames
    }

    /// Iconos de un mazo: los suyos, los de su carpeta, los de su arquetipo o el Pokémon principal de la lista.
    func icons(for deck: Deck, archetypes: ArchetypeStore) -> [String] {
        if let icons = deck.icons, !icons.isEmpty { return icons }
        if let inherited = inheritedIcons(for: deck, archetypes: archetypes), !inherited.isEmpty { return inherited }
        let main = deck.parsed.suggestedName
        return main == "Mazo nuevo" ? [] : [main]
    }

    /// Pokémon de unos mazos, los más usados primero (para sugerir iconos).
    func pokemonSuggestions(in decks: [Deck]) -> [String] {
        var counts: [String: Int] = [:]
        for deck in decks {
            for card in deck.parsed.entries(in: .pokemon) { counts[card.name, default: 0] += card.count }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Al borrar un arquetipo, sus carpetas y mazos quedan sin arquetipo (no se borra nada más).
    func detachArchetype(_ archetype: UUID) {
        for (name, id) in folderArchetypes where id == archetype { touchFolder(name) }
        folderArchetypes = folderArchetypes.filter { $0.value != archetype }
        saveFolders()
        for index in decks.indices where decks[index].archetypeID == archetype {
            decks[index].archetypeID = nil
            unsaved.insert(decks[index].id)
        }
        flush()
    }

    @discardableResult
    func createFolder(named raw: String, archetype: UUID? = nil) -> String? {
        guard let name = validFolderName(raw) else { return nil }
        folders = Self.sortedNames(Set(folders + [name]))
        folderArchetypes[name] = archetype
        folderIDs[name] = UUID()
        touchFolder(name)
        saveFolders()
        return name
    }

    @discardableResult
    func renameFolder(_ oldName: String, to raw: String) -> Bool {
        guard let name = validFolderName(raw, excluding: oldName), name != oldName else { return false }
        folders = Self.sortedNames(Set(folders.filter { $0 != oldName } + [name]))
        folderArchetypes[name] = folderArchetypes.removeValue(forKey: oldName)
        folderIcons[name] = folderIcons.removeValue(forKey: oldName)
        folderIDs[name] = folderIDs.removeValue(forKey: oldName) ?? UUID()
        folderUpdated[oldName] = nil
        touchFolder(name)
        for index in decks.indices where decks[index].folder == oldName {
            decks[index].folder = name
            unsaved.insert(decks[index].id)
        }
        flush()
        saveFolders()
        return true
    }

    /// Elimina la carpeta. Sus mazos pasan a sueltos o, con `deletingDecks`, a la papelera.
    func deleteFolder(_ name: String, deletingDecks: Bool) {
        for deck in decks(in: name) {
            if deletingDecks {
                delete(deck.id)
            } else {
                // Los mazos se quedan en el arquetipo de la carpeta, si tenía.
                move(deck.id, to: folderArchetypes[name].map(DeckLocation.archetype) ?? .loose)
            }
        }
        folders.removeAll { $0 == name }
        folderArchetypes[name] = nil
        folderIcons[name] = nil
        if let id = folderIDs.removeValue(forKey: name) { DeletionLogStore.shared.record(table: "folders", id: id) }
        folderUpdated[name] = nil
        saveFolders()
    }

    private func validFolderName(_ raw: String, excluding current: String? = nil) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errorMessage = "La carpeta necesita un nombre."
        } else if folders.contains(where: { $0 != current && $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            errorMessage = "Ya existe una carpeta llamada «\(name)»."
        } else {
            return name
        }
        return nil
    }

    private func touchFolder(_ name: String) {
        folderUpdated[name] = Date()
    }

    private func saveFolders() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(FoldersFile(folders: folders, archetypes: folderArchetypes, icons: folderIcons,
                                           ids: folderIDs, updated: folderUpdated))
                .write(to: foldersFile, options: .atomic)
        } catch {
            errorMessage = "No se pudieron guardar las carpetas: \(error.localizedDescription)"
        }
    }

    private static func sortedNames(_ names: Set<String>) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Sincronización

    /// Las carpetas como filas de la nube.
    var folderRows: [FolderRow] {
        folders.compactMap { name in
            folderIDs[name].map {
                FolderRow(id: $0, name: name, archetypeID: folderArchetypes[name], icons: folderIcons[name],
                          updatedAt: folderUpdated[name])
            }
        }
    }

    /// Aplica mazos llegados de la nube, sin cambiar sus fechas ni anotarlos como borrados aquí.
    func applyRemote(_ rows: [RemoteRow<Deck>], pending: Set<UUID>) {
        flush()
        var updated = decks
        let result = SyncMerge.apply(rows, to: &updated, pending: pending)
        guard result.changed else { return }
        decks = updated
        for id in result.upserted {
            if let deck = deck(id) { write(deck) }
        }
        for id in result.removed {
            try? PlatformFiles.discard(file(for: id))
        }
        // Un mazo en una carpeta que aquí no existe: se crea la carpeta.
        let missing = Set(decks.compactMap(\.folder)).subtracting(folders)
        if !missing.isEmpty {
            folders = Self.sortedNames(Set(folders).union(missing))
            for name in missing {
                folderIDs[name] = UUID()
                touchFolder(name)
            }
            saveFolders()
        }
        sort()
        if let selectedID, deck(selectedID) == nil { self.selectedID = decks.first?.id }
    }

    /// Aplica carpetas llegadas de la nube: nuevas, renombradas, con otro arquetipo o borradas.
    func applyRemoteFolders(_ rows: [RemoteRow<FolderRow>], pending: Set<UUID>) {
        var current = folderRows
        guard SyncMerge.apply(rows, to: &current, pending: pending).changed else { return }
        let oldNames = Dictionary(folderIDs.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let oldArchetypes = folderArchetypes
        // Si dos equipos crearon una carpeta con el mismo nombre, se queda la más reciente.
        let byName = Dictionary(current.map { ($0.name, $0) }, uniquingKeysWith: { a, b in
            (a.updatedAt ?? SyncDates.legacy) >= (b.updatedAt ?? SyncDates.legacy) ? a : b
        })
        folders = Self.sortedNames(Set(byName.keys))
        folderIDs = byName.mapValues(\.id)
        folderArchetypes = byName.compactMapValues(\.archetypeID)
        folderIcons = byName.compactMapValues(\.icons)
        folderUpdated = byName.compactMapValues(\.updatedAt)
        saveFolders()

        // Renombradas en otro equipo: sus mazos de este equipo cambian de carpeta también.
        for row in byName.values {
            guard let old = oldNames[row.id], old != row.name else { continue }
            for index in decks.indices where decks[index].folder == old {
                decks[index].folder = row.name
                unsaved.insert(decks[index].id)
            }
        }
        flush()
        // Borradas en otro equipo: sus mazos se quedan en el arquetipo que tenía la carpeta, o sueltos.
        for deck in decks {
            guard let name = deck.folder, !folders.contains(name) else { continue }
            move(deck.id, to: oldArchetypes[name].map(DeckLocation.archetype) ?? .loose)
        }
    }

    /// Copia la lista del mazo seleccionado al portapapeles, en formato Limitless.
    func copySelectedList() {
        guard let deck = selectedDeck else { return }
        Clipboard.copy(deck.parsed.export())
    }

    #if os(macOS)
    func revealInFinder(_ id: Deck.ID? = nil) {
        if let id {
            PlatformFiles.reveal(file(for: id), selecting: true)
        } else {
            PlatformFiles.reveal(folder)
        }
    }
    #endif

    /// Escribe a disco todos los mazos con cambios pendientes.
    func flush() {
        saveTask?.cancel()
        let now = Date()
        for id in unsaved {
            guard let index = decks.firstIndex(where: { $0.id == id }) else { continue }
            decks[index].updatedAt = now
            write(decks[index])
        }
        unsaved.removeAll()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func file(for id: Deck.ID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    private func write(_ deck: Deck) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(deck).write(to: file(for: deck.id), options: .atomic)
        } catch {
            errorMessage = "No se pudo guardar «\(deck.name)»: \(error.localizedDescription)"
        }
    }

    private func sort() {
        decks.sort { $0.modified > $1.modified }
    }
}
