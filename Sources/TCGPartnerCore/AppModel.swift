import DeckKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Todos los datos de la app y la sincronización. Lo crea la app de cada plataforma (Mac o iPhone)
/// y se lo pasa a `RootView`.
@MainActor
public final class AppModel: ObservableObject {
    let decks = DeckStore()
    let players = PlayerStore()
    let archetypes = ArchetypeStore(fileName: "archetypes.json", table: "archetypes")
    let matches = MatchStore(fileName: "matches.json", table: "matches")
    let events = EventStore(fileName: "events.json", table: "events")
    let journal = JournalStore(fileName: "journal.json", table: "journal_entries")
    let sync = SyncService()

    public init() {
        sync.attach(.init(decks: decks, players: players, archetypes: archetypes,
                          matches: matches, events: events, journal: journal))
    }

    /// Escribe a disco lo que esté pendiente (al salir de la app o al dejarla en segundo plano).
    public func flush() {
        decks.flush()
        NotificationCenter.default.post(name: .flushRequested, object: nil)
    }
}

/// La interfaz completa, igual en Mac y iPhone, con los datos del modelo.
public struct RootView: View {
    let model: AppModel
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ContentView()
            .environmentObject(model.decks)
            .environmentObject(model.players)
            .environmentObject(model.archetypes)
            .environmentObject(model.matches)
            .environmentObject(model.events)
            .environmentObject(model.journal)
            .environmentObject(model.sync)
            .tint(theme.accent)
            #if os(macOS)
            .onAppear { NSApp.appearance = appearance.nsAppearance }
            .onChange(of: appearance) { NSApp.appearance = appearance.nsAppearance }
            #else
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.sync.requestSync()
                } else {
                    model.flush()
                }
            }
            #endif
    }
}

extension Notification.Name {
    /// Pide a las vistas con cambios sin guardar (como el editor del journal) que los guarden ya.
    static let flushRequested = Notification.Name("TCGPartner.flushRequested")
}

#if os(macOS)
/// Menús de la app de Mac (Archivo, Configuración, Imprimir, Guardar).
public struct MacCommands: Commands {
    @ObservedObject private var store: DeckStore

    public init(model: AppModel) {
        store = model.decks
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nuevo mazo…") {
                NotificationCenter.default.post(name: .newDeckRequested, object: nil)
            }
            .keyboardShortcut("n")
            Button("Pegar lista como mazo nuevo…") {
                NotificationCenter.default.post(name: .pasteDeckRequested, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Nueva carpeta…") {
                NotificationCenter.default.post(name: .newDeckFolderRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Nuevo arquetipo…") {
                NotificationCenter.default.post(name: .newArchetypeRequested, object: nil)
            }
            Button("Registrar partida…") {
                NotificationCenter.default.post(name: .logMatchRequested, object: nil)
            }
            .keyboardShortcut("r")
            Button("Nuevo evento…") {
                NotificationCenter.default.post(name: .newEventRequested, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Copiar lista") { store.copySelectedList() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.selectedID == nil)
            Divider()
            Button("Mostrar mazos en Finder") { store.revealInFinder() }
            Button("Vaciar caché de imágenes") {
                Task {
                    await CardImageService.shared.clearCache()
                    await PokemonIconService.shared.clearCache()
                }
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Configuración…") {
                NotificationCenter.default.post(name: .settingsRequested, object: nil)
            }
            .keyboardShortcut(",")
        }
        CommandGroup(replacing: .printItem) {
            Button("Imprimir o exportar PDF…") {
                NotificationCenter.default.post(name: .printDeckRequested, object: nil)
            }
            .keyboardShortcut("p")
            .disabled(store.selectedID == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Guardar") { store.flush() }
                .keyboardShortcut("s")
        }
    }
}
#endif
