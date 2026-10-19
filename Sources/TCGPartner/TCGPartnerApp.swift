import AppKit
import SwiftUI

@main
struct TCGPartnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DeckStore()

    init() {
        // La app está en español: fechas relativas, días y meses también («hace 2 h», «sáb 11»),
        // aunque el idioma del sistema sea otro. Solo afecta a esta app.
        UserDefaults.standard.set("es_MX", forKey: "AppleLocale")
    }

    @StateObject private var players = PlayerStore()
    @StateObject private var archetypes = ArchetypeStore(fileName: "archetypes.json")
    @StateObject private var matches = MatchStore(fileName: "matches.json")
    @StateObject private var events = EventStore(fileName: "events.json")
    @StateObject private var journal = JournalStore(fileName: "journal.json")
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some Scene {
        Window("TCG - Partner", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(players)
                .environmentObject(archetypes)
                .environmentObject(matches)
                .environmentObject(events)
                .environmentObject(journal)
                .tint(theme.accent)
                .onAppear { NSApp.appearance = appearance.nsAppearance }
                .onChange(of: appearance) { NSApp.appearance = appearance.nsAppearance }
                .frame(minWidth: 900, minHeight: 560)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    store.flush()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necesario cuando se ejecuta con `swift run` (sin bundle .app).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
