import SwiftUI
import TCGPartnerCore

/// App de iPhone: solo la escena. Todo lo demás está en TCGPartnerCore, compartido con la Mac.
@main
struct TCGPartnerApp: App {
    @StateObject private var model = AppModel()

    init() {
        // La app está en español: fechas relativas, días y meses también, aunque el iPhone esté en otro idioma.
        UserDefaults.standard.set("es_MX", forKey: "AppleLocale")
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
