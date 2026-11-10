import DeckKit
import SwiftUI

/// Lo que se puede seleccionar en la barra lateral.
enum SidebarItem: Hashable {
    case dashboard, matches, events, settings
    case archetype(UUID)
    /// Journal de un arquetipo; `entry` abre una anotación concreta.
    case journal(UUID, entry: UUID?)
    case event(UUID)
    case deck(UUID)
}

/// Pestañas del iPhone. En Mac y iPad se usa la barra lateral.
enum AppTab: String, Hashable {
    case dashboard, decks, matches, events, settings
}

/// Hojas que abre la ventana principal (una sola a la vez).
enum ActiveSheet: Identifiable {
    case deckList(DeckEditorRequest)
    case print(Deck.ID)
    case match(MatchRecord, isNew: Bool)
    case matchDetail(UUID)
    case event(TournamentEvent, isNew: Bool)
    case archetype(Archetype, isNew: Bool)
    case icons(IconTarget)

    var id: String {
        switch self {
        case .deckList(let request): "list-\(request.id)"
        case .print(let id): "print-\(id)"
        case .match(let match, _): "match-\(match.id)"
        case .matchDetail(let id): "detail-\(id)"
        case .event(let event, _): "event-\(event.id)"
        case .archetype(let archetype, _): "archetype-\(archetype.id)"
        case .icons(.folder(let name)): "icons-folder-\(name)"
        case .icons(.deck(let id)): "icons-deck-\(id)"
        }
    }
}

/// De quién se editan los iconos.
enum IconTarget {
    case folder(String)
    case deck(Deck.ID)
}

/// Prefijo para arrastrar carpetas (los mazos se arrastran como su UUID).
private let folderDragPrefix = "folder:"

struct ContentView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var archetypes: ArchetypeStore
    @EnvironmentObject private var matches: MatchStore
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var journal: JournalStore

    @State private var selection: SidebarItem? = .dashboard
    @State private var sheet: ActiveSheet?
    @State private var renaming: Deck.ID?
    @State private var newName = ""
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var folderToDelete: String?
    @AppStorage("collapsedDeckFolders") private var collapsedFolders = ""

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// `-initialTab decks` al lanzar abre otra pestaña (para probar en el simulador).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .dashboard
    /// Pila de navegación de cada pestaña.
    @State private var paths: [AppTab: [SidebarItem]] = [:]
    /// En iPhone (ancho compacto) hay pestañas; en iPad, barra lateral como en Mac.
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    private var collapsed: Set<String> {
        Set(collapsedFolders.split(separator: "\n").map(String.init))
    }

    /// Clave de plegado: las carpetas usan su nombre (como antes) y los arquetipos «arquetipo:<id>».
    private func isExpanded(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { expanded in
                var set = collapsed
                if expanded { set.remove(key) } else { set.insert(key) }
                collapsedFolders = set.sorted().joined(separator: "\n")
            })
    }

    private func archetypeKey(_ id: UUID) -> String { "arquetipo:\(id.uuidString)" }

    private var selectedDeckID: UUID? {
        if case .deck(let id) = selection { return id }
        return nil
    }

    private var actions: AppActions {
        AppActions(
            select: { show($0) },
            newDeck: { sheet = .deckList(.fromClipboard(at: store.currentLocation)) },
            newDeckAt: { sheet = .deckList(.fromClipboard(at: $0)) },
            logMatch: { deckID in
                sheet = .match(MatchRecord(deckID: deckID ?? selectedDeckID, eventID: currentEventID), isNew: true)
            },
            logMatchOfKind: { deckID, kind in
                sheet = .match(MatchRecord(deckID: deckID ?? selectedDeckID, eventID: currentEventID, kind: kind), isNew: true)
            },
            editArchetype: { archetype in
                let color = ArchetypeColor.allCases[archetypes.items.count % ArchetypeColor.allCases.count]
                sheet = .archetype(archetype ?? Archetype(name: "", color: color), isNew: archetype == nil)
            },
            editEvent: { event in sheet = .event(event ?? TournamentEvent(), isNew: event == nil) },
            showMatch: { id in sheet = .matchDetail(id) },
            newMatch: { match in sheet = .match(match, isNew: true) })
    }

    /// Evento que se juega hoy, para proponerlo al registrar una partida.
    private var currentEventID: UUID? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return events.items.first { event in
            calendar.startOfDay(for: event.startDate) <= today
                && today <= calendar.startOfDay(for: event.endDate ?? event.startDate)
        }?.id
    }

    var body: some View {
        Group {
            #if os(iOS)
            if isCompact { tabs } else { splitView }
            #else
            splitView
            #endif
        }
        .sheet(item: $sheet, content: sheetContent)
        #if DEBUG
        .onAppear(perform: openDebugSheet)
        #endif
        .onChange(of: selection) {
            if let id = selectedDeckID, store.selectedID != id { store.selectedID = id }
        }
        .onChange(of: store.selectedID) {
            // El mazo recién creado (o el siguiente tras borrar uno) se muestra al momento.
            if let id = store.selectedID {
                if selectedDeckID != nil, selectedDeckID != id { selection = .deck(id) }
                revealSelectedDeck()
            } else if selectedDeckID != nil {
                selection = .dashboard
            }
        }
        .onChange(of: store.decks.count) { old, new in
            if new > old, let id = store.selectedID { show(.deck(id)) }
            #if os(iOS)
            if new < old { pruneMissingPages() }
            #endif
        }
        .modifier(CommandReceivers(actions: actions, onPrint: {
            if let id = selectedDeckID { sheet = .print(id) }
        }, onNewDeck: {
            sheet = .deckList(.create(prefill: "", at: store.currentLocation))
        }, onNewFolder: {
            askForFolderName(.create(moving: nil, archetype: nil))
        }))
        .alert(folderPrompt?.title ?? "", isPresented: Binding(get: { folderPrompt != nil },
                                                                 set: { if !$0 { folderPrompt = nil } }),
               presenting: folderPrompt) { prompt in
            TextField("Nombre", text: $folderName)
            Button("Cancelar", role: .cancel) {}
            Button(prompt.confirmLabel) { commit(prompt) }
        }
        .confirmationDialog("¿Eliminar la carpeta «\(folderToDelete ?? "")»?",
                            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
                            presenting: folderToDelete, actions: deleteFolderActions, message: deleteFolderMessage)
        .alert("Renombrar mazo", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Renombrar") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renaming, !name.isEmpty { store.update(id) { $0.name = name } }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { clearErrors() } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    #if DEBUG
    /// `-openSheet matchDetail|matchEditor|newMatch|eventPage|eventEditor|archetypePage|archetypeEditor|deckPage` al lanzar, para revisar hojas en el simulador.
    private func openDebugSheet() {
        let latest = matches.items.max { $0.date < $1.date }
        switch UserDefaults.standard.string(forKey: "openSheet") {
        case "matchDetail": if let latest { sheet = .matchDetail(latest.id) }
        case "matchEditor": if let latest { sheet = .match(latest, isNew: false) }
        case "newMatch": actions.logMatch(nil)
        case "archetypePage":
            if let archetype = archetypes.items.max(by: { store.decks(ofArchetype: $0.id).count < store.decks(ofArchetype: $1.id).count }) {
                show(.archetype(archetype.id))
            }
        case "archetypeEditor":
            if let archetype = archetypes.items.first { sheet = .archetype(archetype, isNew: false) }
        case "deckPage":
            if let deck = store.decks.max(by: { $0.modified < $1.modified }) { show(.deck(deck.id)) }
        case "eventPage", "eventEditor":
            // El evento con más partidas, para ver la página llena.
            let event = events.items.max { a, b in
                matches.items.filter { $0.eventID == a.id }.count < matches.items.filter { $0.eventID == b.id }.count
            }
            if let event {
                if UserDefaults.standard.string(forKey: "openSheet") == "eventPage" {
                    show(.event(event.id))
                } else {
                    sheet = .event(event, isNew: false)
                }
            }
        default: break
        }
    }
    #endif

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    /// Muestra una sección o página: en la barra lateral la selecciona; en iPhone cambia de pestaña
    /// (secciones principales) o la abre encima de la pestaña actual.
    private func show(_ item: SidebarItem) {
        #if os(iOS)
        if isCompact {
            let root: AppTab? = switch item {
            case .dashboard: .dashboard
            case .matches: .matches
            case .events: .events
            case .settings: .settings
            default: nil
            }
            if let root {
                tab = root
                paths[root] = []
            } else if paths[tab]?.last != item {
                paths[tab, default: []].append(item)
            }
            return
        }
        #endif
        selection = item
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .deckList(let request): PasteDeckSheet(request: request)
        case .print(let id): PrintDeckSheet(deckID: id)
        case .match(let match, let isNew): MatchEditor(match: match, isNew: isNew)
        case .matchDetail(let id):
            MatchDetailView(matchID: id, actions: actions) { match in self.sheet = .match(match, isNew: false) }
        case .event(let event, let isNew): EventEditor(event: event, isNew: isNew)
        case .archetype(let archetype, let isNew): ArchetypeEditor(archetype: archetype, isNew: isNew)
        case .icons(let target): iconsEditor(target)
        }
    }

    @ViewBuilder
    private func iconsEditor(_ target: IconTarget) -> some View {
        switch target {
        case .folder(let folder):
            let archetype = archetypes.item(store.folderArchetypes[folder])
            IconsEditorSheet(title: "Iconos de la carpeta «\(folder)»",
                             names: store.folderIcons[folder] ?? [],
                             inherited: archetype?.iconNames ?? [],
                             inheritedFrom: archetype.map { "su arquetipo «\($0.name)»" },
                             suggestions: store.pokemonSuggestions(in: store.decks(in: folder))) { names in
                store.setIcons(names, forFolder: folder)
            }
        case .deck(let id):
            if let deck = store.deck(id) {
                let inherited = store.inheritedIcons(for: deck, archetypes: archetypes)
                IconsEditorSheet(title: "Iconos de «\(deck.name)»",
                                 names: deck.icons ?? [],
                                 inherited: inherited ?? [deck.parsed.suggestedName],
                                 inheritedFrom: deck.folder.map { "la carpeta «\($0)»" }
                                     ?? archetypes.item(store.archetypeID(of: deck)).map { "su arquetipo «\($0.name)»" },
                                 suggestions: store.pokemonSuggestions(in: [deck])) { names in
                    store.setIcons(names, forDeck: id)
                }
            }
        }
    }

    @ViewBuilder
    private func deleteFolderActions(_ folder: String) -> some View {
        let count = store.decks(in: folder).count
        Button(count == 0 ? "Eliminar carpeta" : "Eliminar carpeta y conservar los mazos") {
            store.deleteFolder(folder, deletingDecks: false)
        }
        if count > 0 {
            Button("Eliminar carpeta y mover sus \(count == 1 ? "mazo" : "\(count) mazos") a la papelera", role: .destructive) {
                store.deleteFolder(folder, deletingDecks: true)
            }
        }
        Button("Cancelar", role: .cancel) {}
    }

    private func deleteFolderMessage(_ folder: String) -> some View {
        let count = store.decks(in: folder).count
        return Text(count == 0 ? "La carpeta está vacía." :
                    "Contiene \(count == 1 ? "1 mazo" : "\(count) mazos"). Si los conservas, quedan en el arquetipo de la carpeta (o sueltos).")
    }

    private var errorMessage: String? {
        store.errorMessage ?? archetypes.errorMessage ?? matches.errorMessage ?? events.errorMessage ?? journal.errorMessage
    }

    private func clearErrors() {
        store.errorMessage = nil
        archetypes.errorMessage = nil
        matches.errorMessage = nil
        events.errorMessage = nil
        journal.errorMessage = nil
    }

    // MARK: - Detalle

    private var detail: some View {
        page(selection ?? .dashboard)
    }

    private var matchesPage: some View {
        MatchesView(actions: actions) { sheet = .match($0, isNew: false) }
            .navigationTitle("Partidas")
    }

    private var eventsPage: some View {
        EventsView(actions: actions)
            .navigationTitle("Eventos")
    }

    /// Lo que se ve al ir a algo que ya no existe (p. ej. un mazo borrado en otro dispositivo).
    @ViewBuilder
    private func missing(_ fallback: some View) -> some View {
        if isCompact {
            ContentUnavailableView("Ya no existe", systemImage: "questionmark.folder",
                                   description: Text("Se eliminó o se movió."))
        } else {
            fallback
        }
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .matches:
            matchesPage
        case .events:
            eventsPage
        case .settings:
            SettingsView()
        case .event(let id):
            if let event = events.item(id) {
                EventPage(event: event, actions: actions)
                    .id(id)
            } else {
                missing(eventsPage)
            }
        case .archetype(let id):
            if let archetype = archetypes.item(id) {
                ArchetypeView(archetype: archetype, actions: actions)
                    .id(id)
            } else {
                missing(dashboard)
            }
        case .journal(let id, let entry):
            if let archetype = archetypes.item(id) {
                JournalView(archetype: archetype, initialEntry: entry, actions: actions)
                    .id(id)
            } else {
                missing(dashboard)
            }
        case .deck(let id):
            if let deck = store.deck(id) {
                deckDetail(deck)
            } else {
                missing(dashboard)
            }
        case .dashboard:
            dashboard
        }
    }

    private func deckDetail(_ deck: Deck) -> some View {
        DeckView(deck: deck, onEditList: { sheet = .deckList(.edit(deck.id)) },
                 onPrint: { sheet = .print(deck.id) }, onLogMatch: { actions.logMatch(deck.id) },
                 onEditIcons: { sheet = .icons(.deck(deck.id)) })
            .id(deck.id)
            .navigationTitle(deck.name)
            .windowSubtitle(deck.parsed.summary)
    }

    private var dashboard: some View {
        DashboardView(actions: actions)
            .navigationTitle("Dashboard")
    }

    // MARK: - Barra lateral

    private var sortedArchetypes: [Archetype] {
        archetypes.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            navigationSection
            archetypesSection
            decksSection
        }
        .onDeleteKey {
            if let id = selectedDeckID { store.delete(id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(isSelected: selection == .settings) { selection = .settings }
        }
        .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 400)
        .toolbar {
            ToolbarItem {
                Button(action: actions.newDeck) {
                    Label("Pegar lista", systemImage: "doc.on.clipboard")
                }
                .help("Nuevo mazo desde el portapapeles (⇧⌘V)")
            }
        }
    }

    private var navigationSection: some View {
        Section {
            Label("Dashboard", systemImage: "square.grid.2x2")
                .tag(SidebarItem.dashboard)
            Label("Partidas", systemImage: "list.bullet.rectangle")
                .badge(matches.items.count)
                .tag(SidebarItem.matches)
            Label("Eventos", systemImage: "calendar")
                .badge(events.items.filter { $0.isUpcoming() }.count)
                .tag(SidebarItem.events)
        }
    }

    private var archetypesSection: some View {
        Section {
            ForEach(sortedArchetypes) { archetypeGroup($0) }
            if archetypes.items.isEmpty {
                Button { actions.editArchetype(nil) } label: {
                    Label("Crear un arquetipo", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        } header: {
            SidebarHeader(title: "Arquetipos", symbol: "plus", help: "Nuevo arquetipo") {
                actions.editArchetype(nil)
            }
        }
    }

    private var decksSection: some View {
        Section {
            ForEach(store.folders(of: nil), id: \.self) { folderGroup($0) }
            rows(store.decks(at: .loose))
        } header: {
            SidebarHeader(title: "Mazos", symbol: "folder.badge.plus", help: "Nueva carpeta (⇧⌘N)") {
                askForFolderName(.create(moving: nil, archetype: nil))
            }
        }
    }

    private func archetypeGroup(_ archetype: Archetype) -> some View {
        let folders = store.folders(of: archetype.id)
        let looseDecks = store.decks(at: .archetype(archetype.id))
        return DisclosureGroup(isExpanded: isExpanded(archetypeKey(archetype.id))) {
            ForEach(folders, id: \.self) { folderGroup($0) }
            rows(looseDecks)
            if folders.isEmpty && looseDecks.isEmpty {
                Text(isCompact ? "Sin mazos" : "Arrastra carpetas o mazos aquí")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            link(.archetype(archetype.id)) {
                ArchetypeLabel(archetype: archetype, count: store.decks(ofArchetype: archetype.id).count) { payloads in
                    dropOnArchetype(payloads, archetype.id)
                }
            }
            .contextMenu { archetypeMenu(archetype) }
        }
    }

    @ViewBuilder
    private func archetypeMenu(_ archetype: Archetype) -> some View {
        Button("Nuevo mazo aquí (pegar lista)…") { sheet = .deckList(.fromClipboard(at: .archetype(archetype.id))) }
        Button("Nueva carpeta…") { askForFolderName(.create(moving: nil, archetype: archetype.id)) }
        Button("Registrar partida…") { actions.logMatch(store.decks(ofArchetype: archetype.id).first?.id) }
        Divider()
        Button("Editar arquetipo…") { actions.editArchetype(archetype) }
    }

    private func folderGroup(_ folder: String) -> some View {
        let decks = store.decks(in: folder)
        return DisclosureGroup(isExpanded: isExpanded(folder)) {
            if decks.isEmpty {
                Text(isCompact ? "Vacía" : "Vacía · arrastra mazos aquí")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            rows(decks)
        } label: {
            DeckFolderLabel(name: folder, count: decks.count, icons: store.folderIcons[folder]) { id in
                store.move(id, to: .folder(folder))
            }
                .draggable(folderDragPrefix + folder)
                .contextMenu { folderMenu(folder) }
        }
    }

    private func rows(_ decks: [Deck]) -> some View {
        ForEach(decks) { deck in
            link(.deck(deck.id)) {
                DeckRow(deck: deck, icons: store.icons(for: deck, archetypes: archetypes))
            }
                .draggable(deck.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    // Soltar un mazo sobre otro lo lleva al mismo sitio.
                    moveDropped(ids, to: store.location(of: deck))
                }
                .contextMenu { deckMenu(deck) }
        }
    }

    @ViewBuilder
    private func deckMenu(_ deck: Deck) -> some View {
        Button("Renombrar…") {
            newName = deck.name
            renaming = deck.id
        }
        Button("Editar lista…") { sheet = .deckList(.edit(deck.id)) }
        Button("Registrar partida…") { actions.logMatch(deck.id) }
        Button("Imprimir o exportar PDF…") { sheet = .print(deck.id) }
        Button("Iconos…") { sheet = .icons(.deck(deck.id)) }
        Menu("Mover a") { moveMenu(deck) }
        Menu("Estado") {
            ForEach(DeckStatus.allCases) { status in
                Button(status.title) { store.update(deck.id) { $0.status = status } }
                    .disabled(deck.currentStatus == status)
            }
        }
        Button("Duplicar") { store.duplicate(deck.id) }
        #if os(macOS)
        Button("Mostrar en Finder") { store.revealInFinder(deck.id) }
        #endif
        Divider()
        Button("Mover a la papelera", role: .destructive) { store.delete(deck.id) }
    }

    @ViewBuilder
    private func moveMenu(_ deck: Deck) -> some View {
        let here = store.location(of: deck)
        ForEach(sortedArchetypes) { archetype in
            Menu(archetype.name) {
                Button("Directamente en \(archetype.name)") { store.move(deck.id, to: .archetype(archetype.id)) }
                    .disabled(here == .archetype(archetype.id))
                ForEach(store.folders(of: archetype.id), id: \.self) { folder in
                    Button(folder) { store.move(deck.id, to: .folder(folder)) }
                        .disabled(here == .folder(folder))
                }
            }
        }
        if !archetypes.items.isEmpty { Divider() }
        Button("Sin carpeta ni arquetipo") { store.move(deck.id, to: .loose) }
            .disabled(here == .loose)
        ForEach(store.folders(of: nil), id: \.self) { folder in
            Button(folder) { store.move(deck.id, to: .folder(folder)) }
                .disabled(here == .folder(folder))
        }
        Divider()
        Button("Carpeta nueva…") { askForFolderName(.create(moving: deck.id, archetype: store.archetypeID(of: deck))) }
    }

    @ViewBuilder
    private func folderMenu(_ folder: String) -> some View {
        Button("Nuevo mazo aquí (pegar lista)…") { sheet = .deckList(.fromClipboard(at: .folder(folder))) }
        Button("Renombrar…") { askForFolderName(.rename(folder)) }
        Button("Iconos…") { sheet = .icons(.folder(folder)) }
        Menu("Arquetipo") {
            Button("Ninguno") { store.setArchetype(nil, forFolder: folder) }
                .disabled(store.folderArchetypes[folder] == nil)
            Divider()
            ForEach(sortedArchetypes) { archetype in
                Button(archetype.name) { store.setArchetype(archetype.id, forFolder: folder) }
                    .disabled(store.folderArchetypes[folder] == archetype.id)
            }
        }
        Divider()
        Button("Eliminar carpeta…", role: .destructive) { folderToDelete = folder }
    }

    /// Fila que lleva a una página: en la barra lateral se selecciona; en iPhone es un enlace.
    @ViewBuilder
    private func link(_ item: SidebarItem, @ViewBuilder label: () -> some View) -> some View {
        if isCompact {
            NavigationLink(value: item, label: label)
        } else {
            label().tag(item)
        }
    }

    // MARK: - Acciones

    /// Abre la carpeta y el arquetipo del mazo seleccionado si estaban plegados.
    private func revealSelectedDeck() {
        guard let deck = store.selectedDeck else { return }
        if let folder = deck.folder { isExpanded(folder).wrappedValue = true }
        if let archetype = store.archetypeID(of: deck) { isExpanded(archetypeKey(archetype)).wrappedValue = true }
    }

    private func moveDropped(_ ids: [String], to location: DeckLocation) -> Bool {
        let decks = ids.compactMap(UUID.init(uuidString:)).filter { store.deck($0) != nil }
        decks.forEach { store.move($0, to: location) }
        return !decks.isEmpty
    }

    /// Sobre un arquetipo se pueden soltar mazos (quedan directamente en él) o carpetas (se relacionan con él).
    private func dropOnArchetype(_ payloads: [String], _ archetype: UUID) -> Bool {
        var handled = false
        for payload in payloads {
            if payload.hasPrefix(folderDragPrefix) {
                store.setArchetype(archetype, forFolder: String(payload.dropFirst(folderDragPrefix.count)))
                handled = true
            } else if let id = UUID(uuidString: payload), store.deck(id) != nil {
                store.move(id, to: .archetype(archetype))
                handled = true
            }
        }
        return handled
    }

    private func askForFolderName(_ prompt: FolderPrompt) {
        if case .rename(let name) = prompt { folderName = name } else { folderName = "" }
        folderPrompt = prompt
    }

    private func commit(_ prompt: FolderPrompt) {
        switch prompt {
        case .create(let deckID, let archetype):
            guard let folder = store.createFolder(named: folderName, archetype: archetype) else { return }
            if let deckID { store.move(deckID, to: .folder(folder)) }
            if let archetype { isExpanded(archetypeKey(archetype)).wrappedValue = true }
        case .rename(let old):
            let wasCollapsed = collapsed.contains(old)
            guard store.renameFolder(old, to: folderName) else { return }
            if wasCollapsed {
                isExpanded(old).wrappedValue = true
                isExpanded(folderName.trimmingCharacters(in: .whitespacesAndNewlines)).wrappedValue = false
            }
        }
    }
}

/// Comandos del menú que llegan como notificaciones.
private struct CommandReceivers: ViewModifier {
    let actions: AppActions
    let onPrint: () -> Void
    let onNewDeck: () -> Void
    let onNewFolder: () -> Void

    private func publisher(_ name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }

    func body(content: Content) -> some View {
        content
            .onReceive(publisher(.printDeckRequested)) { _ in onPrint() }
            .onReceive(publisher(.newDeckRequested)) { _ in onNewDeck() }
            .onReceive(publisher(.pasteDeckRequested)) { _ in actions.newDeck() }
            .onReceive(publisher(.newDeckFolderRequested)) { _ in onNewFolder() }
            .onReceive(publisher(.logMatchRequested)) { _ in actions.logMatch(nil) }
            .onReceive(publisher(.newEventRequested)) { _ in actions.editEvent(nil) }
            .onReceive(publisher(.newArchetypeRequested)) { _ in actions.editArchetype(nil) }
            .onReceive(publisher(.settingsRequested)) { _ in actions.select(.settings) }
    }
}

enum FolderPrompt {
    /// Crea una carpeta (opcionalmente dentro de un arquetipo) y, si se indica, mueve un mazo a ella.
    case create(moving: Deck.ID?, archetype: UUID?)
    case rename(String)

    var title: String {
        switch self {
        case .create: "Nueva carpeta"
        case .rename(let name): "Renombrar «\(name)»"
        }
    }

    var confirmLabel: String {
        switch self {
        case .create: "Crear"
        case .rename: "Renombrar"
        }
    }
}

/// Cabecera de sección de la barra lateral con un botón a la derecha.
/// El botón queda alineado con los contadores de las filas, no pegado al borde.
struct SidebarHeader: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 4)
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(help)
        }
        .padding(.trailing, 8)
    }
}

/// Arquetipo en la barra lateral; acepta mazos y carpetas arrastrados.
struct ArchetypeLabel: View {
    let archetype: Archetype
    let count: Int
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            ArchetypeIcon(archetype: archetype, size: 20)
            Text(archetype.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 5).fill(isTargeted ? archetype.color.color.opacity(0.3) : .clear))
        .dropDestination(for: String.self) { payloads, _ in onDrop(payloads) } isTargeted: { isTargeted = $0 }
    }
}

/// Carpeta en la barra lateral; acepta mazos arrastrados.
struct DeckFolderLabel: View {
    let name: String
    let count: Int
    /// Iconos propios de la carpeta; si no tiene, se muestra el icono de carpeta.
    var icons: [String]?
    let onDrop: (Deck.ID) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 7) {
            if let icons, !icons.isEmpty {
                PokemonIcons(names: icons, size: 22)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
            }
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 5).fill(isTargeted ? Color.accentColor.opacity(0.25) : .clear))
        .dropDestination(for: String.self) { ids, _ in
            let decks = ids.compactMap(UUID.init(uuidString:))
            decks.forEach(onDrop)
            return !decks.isEmpty
        } isTargeted: { isTargeted = $0 }
    }
}

struct DeckRow: View {
    let deck: Deck
    /// Iconos de Pokémon del mazo (como en Limitless).
    let icons: [String]

    var body: some View {
        let parsed = deck.parsed
        HStack(spacing: 8) {
            PokemonIcons(names: icons, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !parsed.isStandardSize {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text("\(parsed.totalCount) cartas · ")
                        + Text(deck.modified, format: .relative(presentation: .named))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

extension Notification.Name {
    static let newDeckRequested = Notification.Name("TCGPartner.newDeckRequested")
    static let pasteDeckRequested = Notification.Name("TCGPartner.pasteDeckRequested")
    static let printDeckRequested = Notification.Name("TCGPartner.printDeckRequested")
    static let newDeckFolderRequested = Notification.Name("TCGPartner.newDeckFolderRequested")
    static let logMatchRequested = Notification.Name("TCGPartner.logMatchRequested")
    static let newEventRequested = Notification.Name("TCGPartner.newEventRequested")
    static let newArchetypeRequested = Notification.Name("TCGPartner.newArchetypeRequested")
    static let settingsRequested = Notification.Name("TCGPartner.settingsRequested")
}

// MARK: - iPhone: pestañas

#if os(iOS)
extension ContentView {
    var tabs: some View {
        TabView(selection: $tab) {
            stack(.dashboard) { dashboard }
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(AppTab.dashboard)
            stack(.decks) { decksTab }
                .tabItem { Label("Mazos", systemImage: "rectangle.stack") }
                .tag(AppTab.decks)
            stack(.matches) { matchesPage }
                .tabItem { Label("Partidas", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.matches)
            stack(.events) { eventsPage }
                .tabItem { Label("Eventos", systemImage: "calendar") }
                .badge(events.items.filter { $0.isUpcoming() }.count)
                .tag(AppTab.events)
            stack(.settings) { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onChange(of: paths) { syncSelectedDeck() }
        .onChange(of: tab) { syncSelectedDeck() }
    }

    private func stack(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })) {
            root().navigationDestination(for: SidebarItem.self) { page($0) }
        }
    }

    /// Arquetipos, carpetas y mazos (lo que en Mac está en la barra lateral).
    private var decksTab: some View {
        List {
            archetypesSection
            decksSection
        }
        .navigationTitle("Mazos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { actions.newDeck() } label: { Label("Nuevo mazo (pegar lista)", systemImage: "doc.on.clipboard") }
                    Button { actions.editArchetype(nil) } label: { Label("Nuevo arquetipo", systemImage: "square.stack.3d.up") }
                    Button { askForFolderName(.create(moving: nil, archetype: nil)) } label: {
                        Label("Nueva carpeta", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Nuevo", systemImage: "plus")
                }
            }
        }
    }

    /// El mazo que está a la vista es el seleccionado (lo usan «Registrar partida», imprimir, etc.).
    private func syncSelectedDeck() {
        if case .deck(let id) = paths[tab]?.last, store.selectedID != id { store.selectedID = id }
    }

    /// Cierra las páginas de mazos que ya no existen.
    func pruneMissingPages() {
        for (key, path) in paths {
            let kept = path.filter { item in
                if case .deck(let id) = item { return store.deck(id) != nil }
                return true
            }
            if kept.count != path.count { paths[key] = kept }
        }
    }
}
#endif
