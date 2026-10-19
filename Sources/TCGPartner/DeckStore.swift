import AppKit
import DeckKit
import Foundation

/// Un mazo guardado. El texto de la lista es la fuente de verdad: se vuelve a leer con `DeckParser`.
struct Deck: Identifiable, Codable, Hashable {
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
    var modified: Date

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

/// Formato de folders.json: las carpetas y, opcionalmente, el arquetipo de cada una.
private struct FoldersFile: Codable {
    var folders: [String]
    var archetypes: [String: UUID]
    /// Iconos propios de cada carpeta (opcional: los archivos anteriores no lo tienen).
    var icons: [String: [String]]?
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
            let file = data.flatMap { try? JSONDecoder().decode(FoldersFile.self, from: $0) }
                ?? FoldersFile(folders: data.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [], archetypes: [:], icons: nil)
            // También las carpetas que usan los mazos, por si folders.json se perdió.
            folders = Self.sortedNames(Set(file.folders + decks.compactMap(\.folder)))
            folderArchetypes = file.archetypes.filter { folders.contains($0.key) }
            folderIcons = (file.icons ?? [:]).filter { folders.contains($0.key) }
            if selectedID == nil || deck(selectedID!) == nil { selectedID = decks.first?.id }
        } catch {
            errorMessage = "No se pudo abrir la carpeta de mazos: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func create(name: String, list: String, at location: DeckLocation = .loose) -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var deck = Deck(id: UUID(), name: trimmed.isEmpty ? DeckParser.parse(list).suggestedName : trimmed,
                        list: list, notes: "", status: .testing, created: Date(), modified: Date())
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
            try FileManager.default.trashItem(at: file(for: id), resultingItemURL: nil)
        } catch {
            errorMessage = "No se pudo eliminar el mazo: \(error.localizedDescription)"
            return
        }
        decks.remove(at: index)
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
        saveFolders()
    }

    // MARK: - Iconos

    /// Iconos propios de una carpeta (vacío = usar los de su arquetipo).
    func setIcons(_ icons: [String], forFolder name: String) {
        guard folders.contains(name) else { return }
        folderIcons[name] = icons.isEmpty ? nil : icons
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
        saveFolders()
        return name
    }

    @discardableResult
    func renameFolder(_ oldName: String, to raw: String) -> Bool {
        guard let name = validFolderName(raw, excluding: oldName), name != oldName else { return false }
        folders = Self.sortedNames(Set(folders.filter { $0 != oldName } + [name]))
        folderArchetypes[name] = folderArchetypes.removeValue(forKey: oldName)
        folderIcons[name] = folderIcons.removeValue(forKey: oldName)
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

    private func saveFolders() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(FoldersFile(folders: folders, archetypes: folderArchetypes, icons: folderIcons))
                .write(to: foldersFile, options: .atomic)
        } catch {
            errorMessage = "No se pudieron guardar las carpetas: \(error.localizedDescription)"
        }
    }

    private static func sortedNames(_ names: Set<String>) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Copia la lista del mazo seleccionado al portapapeles, en formato Limitless.
    func copySelectedList() {
        guard let deck = selectedDeck else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(deck.parsed.export(), forType: .string)
    }

    func revealInFinder(_ id: Deck.ID? = nil) {
        if let id {
            NSWorkspace.shared.activateFileViewerSelecting([file(for: id)])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    /// Escribe a disco todos los mazos con cambios pendientes.
    func flush() {
        saveTask?.cancel()
        for id in unsaved {
            if let deck = deck(id) { write(deck) }
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
