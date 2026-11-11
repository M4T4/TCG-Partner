import AppKit
import SwiftUI
import TCGPartnerCore

/// App de Mac: solo la ventana, los menús y el ciclo de vida. Todo lo demás está en TCGPartnerCore,
/// compartido con la app de iPhone.
@main
struct TCGPartnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // La app está en español: fechas relativas, días y meses también («hace 2 h», «sáb 11»),
        // aunque el idioma del sistema sea otro. Solo afecta a esta app.
        UserDefaults.standard.set("es_MX", forKey: "AppleLocale")
    }

    var body: some Scene {
        Window("TCG - Partner", id: "main") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flush()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.flush()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { MacCommands(model: model) }
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
